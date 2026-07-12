// One source file → one output. Orchestrates probe → command plan → sequential
// execution with multi-phase progress → atomic rename (PRD §5.3/§5.4):
// - writes to a hidden temp name in the DESTINATION directory, renames on success
//   (same-volume rename = atomic; never a partial file at the final name)
// - collision-safe final naming: "-2", "-3", … suffixes, never silent overwrite (B8)
// - GIF progress phases: palette 0–45%, render 45–90%, gifsicle 90–100%

import Foundation

public struct JobFailure: Error, Sendable {
    public var step: String          // "probe" | "ffmpeg" | "gifsicle"
    public var exitCode: Int32?
    public var stderrTail: String    // surfaced in the failure UX (PRD §5.5)
    public var wasCancelled: Bool

    public init(step: String, exitCode: Int32?, stderrTail: String, wasCancelled: Bool) {
        self.step = step
        self.exitCode = exitCode
        self.stderrTail = stderrTail
        self.wasCancelled = wasCancelled
    }
}

public final class ConversionJob: @unchecked Sendable {
    public let source: URL
    public let preset: Preset
    private let tools: Tools
    private let lock = NSLock()
    private var currentRunner: ProcessRunner?
    private var cancelled = false

    public init(source: URL, preset: Preset, tools: Tools) {
        self.source = source
        self.preset = preset
        self.tools = tools
    }

    // MARK: naming

    /// "clip.mov" + mp4H264 → "clip-h264_crf33.mp4" next to the source; "-2" on clash.
    public static func destination(for source: URL, preset: Preset) -> URL {
        let dir = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(
            "\(base)\(preset.filenameSuffix).\(preset.fileExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(
                "\(base)\(preset.filenameSuffix)-\(counter).\(preset.fileExtension)")
            counter += 1
        }
        return candidate
    }

    // MARK: execution

    /// Blocking; call from a background task. Returns the final output URL.
    public func run(onProgress: (@Sendable (Double?) -> Void)? = nil) throws -> URL {
        let options = preset.options

        let info: MediaInfo
        do {
            // Register the probe's runner so cancel() reaches ffprobe too — otherwise
            // a hung probe would be uncancellable and stall the whole serial queue.
            let probeRunner = ProcessRunner()
            lock.lock()
            currentRunner = probeRunner
            let alreadyCancelled = cancelled
            lock.unlock()
            defer { lock.lock(); currentRunner = nil; lock.unlock() }
            if alreadyCancelled { throw MediaProbeError.cancelled }
            info = try MediaProbe.probe(source: source, ffprobe: tools.ffprobe, runner: probeRunner)
        } catch let error as MediaProbeError {
            switch error {
            case .cancelled:
                throw JobFailure(step: "probe", exitCode: nil, stderrTail: "", wasCancelled: true)
            case .ffprobeFailed(let exitCode, let stderr):
                throw JobFailure(step: "probe", exitCode: exitCode, stderrTail: stderr, wasCancelled: false)
            case .unparseableOutput:
                throw JobFailure(step: "probe", exitCode: nil,
                                 stderrTail: "unparseable ffprobe output", wasCancelled: false)
            }
        }
        let effectiveDuration = info.effectiveDuration(trim: options.trim)

        let destination = Self.destination(for: source, preset: preset)
        // Temp in the destination dir so the final step is a same-volume atomic rename.
        // Hidden (dot prefix) but keeping the REAL extension — ffmpeg infers the muxer
        // from it ("Unable to choose an output format" otherwise).
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".converting-\(UUID().uuidString.prefix(8))-\(destination.lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: temp) }

        switch options.format {
        case .mp4:
            let args = FFmpegCommandBuilder.mp4Command(
                source: source, destination: temp, options: options, audio: info.audioPlan)
            try runStep(name: "ffmpeg", tool: tools.ffmpeg, arguments: args,
                        effectiveDuration: effectiveDuration,
                        progressRange: 0.0...1.0, onProgress: onProgress)

        case .gif:
            let palette = FileManager.default.temporaryDirectory
                .appendingPathComponent("vid2gif_palette_\(UUID().uuidString.prefix(8)).png")
            defer { try? FileManager.default.removeItem(at: palette) }

            try runStep(name: "ffmpeg", tool: tools.ffmpeg,
                        arguments: FFmpegCommandBuilder.gifPalettePass(
                            source: source, palette: palette, options: options),
                        effectiveDuration: effectiveDuration,
                        progressRange: 0.0...0.45, onProgress: onProgress)
            guard let paletteSize = try? palette.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  paletteSize > 0 else {
                throw JobFailure(step: "ffmpeg", exitCode: nil,
                                 stderrTail: "palette generation produced an empty file",
                                 wasCancelled: isCancelled)
            }
            try runStep(name: "ffmpeg", tool: tools.ffmpeg,
                        arguments: FFmpegCommandBuilder.gifRenderPass(
                            source: source, palette: palette, destination: temp, options: options),
                        effectiveDuration: effectiveDuration,
                        progressRange: 0.45...0.9, onProgress: onProgress)
            if options.optimizeGif {
                do {
                    try runStep(name: "gifsicle", tool: tools.gifsicle,
                                arguments: FFmpegCommandBuilder.gifsicleCommand(target: temp, options: options),
                                effectiveDuration: nil,
                                progressRange: 0.9...1.0, onProgress: onProgress)
                } catch let failure as JobFailure where failure.wasCancelled {
                    throw failure
                } catch {
                    // Canonical spec (vid2gif_func.sh:277): ANY gifsicle failure —
                    // nonzero exit AND launch errors (missing/non-executable binary,
                    // which ProcessRunner throws as a plain Error, not a JobFailure)
                    // — is a warning; the rendered GIF is kept, unoptimized.
                }
            }
        }

        // A cancel accepted at ANY point before publication must win: without this
        // re-check, a cancel landing in the window between the last step clearing
        // currentRunner and the rename below would still publish the file and
        // report success (panel finding).
        if isCancelled {
            throw JobFailure(step: "publish", exitCode: nil, stderrTail: "", wasCancelled: true)
        }

        // Atomic publish. destination() re-checks collisions, but check-then-move is
        // not atomic system-wide — on a lost race (external writer claims the name),
        // recompute the next free suffix and retry.
        var finalURL = Self.destination(for: source, preset: preset)
        var attempts = 0
        while true {
            do {
                try FileManager.default.moveItem(at: temp, to: finalURL)
                break
            } catch let error as CocoaError where error.code == .fileWriteFileExists && attempts < 5 {
                attempts += 1
                finalURL = Self.destination(for: source, preset: preset)
            }
        }
        onProgress?(1.0)
        return finalURL
    }

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        let runner = currentRunner
        lock.unlock()
        runner?.cancel()
    }

    // MARK: -

    private func runStep(name: String,
                         tool: URL,
                         arguments: [String],
                         effectiveDuration: Double?,
                         progressRange: ClosedRange<Double>,
                         onProgress: (@Sendable (Double?) -> Void)?) throws {
        // Publish the runner and read the cancel flag in ONE critical section: a
        // cancel() before it marks `cancelled` (checked below); a cancel() after it
        // sees `currentRunner` and reaches the runner, which refuses to launch or
        // SIGTERMs — no window where a cancel is silently lost.
        let runner = ProcessRunner()
        lock.lock()
        currentRunner = runner
        let alreadyCancelled = cancelled
        lock.unlock()
        defer { lock.lock(); currentRunner = nil; lock.unlock() }
        if alreadyCancelled {
            throw JobFailure(step: name, exitCode: nil, stderrTail: "", wasCancelled: true)
        }

        let parserBox = ParserBox()
        let result = try runner.run(tool: tool, arguments: arguments) { chunk in
            guard let onProgress else { return }
            for snapshot in parserBox.consume(chunk) {
                if let fraction = ProgressParser.fraction(of: snapshot, effectiveDuration: effectiveDuration) {
                    let span = progressRange.upperBound - progressRange.lowerBound
                    onProgress(progressRange.lowerBound + fraction * span)
                } else {
                    onProgress(nil) // indeterminate (duration N/A)
                }
            }
        }
        guard result.exitCode == 0, !result.wasCancelled else {
            throw JobFailure(step: name, exitCode: result.exitCode,
                             stderrTail: result.stderrTail, wasCancelled: result.wasCancelled)
        }
    }
}

/// ProgressParser is a mutating struct; the chunk callback arrives on a background
/// queue, so serialize access.
final class ParserBox: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = ProgressParser()
    func consume(_ chunk: String) -> [ProgressSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return parser.consume(chunk)
    }
}
