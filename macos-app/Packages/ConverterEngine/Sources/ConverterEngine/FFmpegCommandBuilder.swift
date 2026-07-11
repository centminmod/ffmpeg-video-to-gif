// Builds the exact argument arrays the engine executes. This is a port of
// vid2gif_pro's command construction (vid2gif_func.sh, the canonical spec) with the
// PRD §1 bug fixes applied — each deviation is annotated with its bug ID (B1–B10).
// Pure functions over value types: golden-parity tests assert these arrays directly.

import Foundation

public struct AudioPlan: Equatable, Sendable {
    /// B6/B10 fix: decided by MediaProbe's parsed JSON (real audio stream present +
    /// its codec), never by ffprobe's exit status.
    public enum Mode: Equatable, Sendable {
        case none            // -an
        case copy            // -c:a copy   (already AAC — B6 fix)
        case transcodeAAC    // -c:a aac -b:a 128k (script behavior, kept for non-AAC)
    }
    public var mode: Mode
    public init(mode: Mode) { self.mode = mode }

    public static func forSource(hasAudio: Bool, audioCodec: String?) -> AudioPlan {
        guard hasAudio else { return AudioPlan(mode: .none) }
        return AudioPlan(mode: audioCodec == "aac" ? .copy : .transcodeAAC)
    }

    var arguments: [String] {
        switch mode {
        case .none: ["-an"]
        case .copy: ["-c:a", "copy"]
        case .transcodeAAC: ["-c:a", "aac", "-b:a", "128k"]
        }
    }
}

public enum FFmpegCommandBuilder {

    // MARK: shared pieces

    /// B1/B4 fix: trim options are INPUT-side (before -i) — fast seek, and both GIF
    /// passes see identical trimming. (Script placed them after -i, and pass 2 placed
    /// them between the two -i inputs, which hard-fails on ffmpeg 8.)
    static func trimArguments(_ trim: Trim) -> [String] {
        var args: [String] = []
        if let start = trim.start { args += ["-ss", start] }
        if let end = trim.end { args += ["-to", end] }
        return args
    }

    /// Video filter chain in script order: scale, then fps (crop is a v1.x addition).
    static func filterChain(options: ConversionOptions) -> String? {
        var filters: [String] = []
        if let scale = options.scale.filter { filters.append(scale) }
        if case .gif = options.format {
            filters.append("fps=\(options.fps ?? 10)") // script default_gif_fps=10
        }
        return filters.isEmpty ? nil : filters.joined(separator: ",")
    }

    // B8 fix: -v error (pass 2 used -v quiet, hiding failures); -nostdin because the
    // engine owns stdin; -progress pipe:1 feeds ProgressParser. -y is safe: the engine
    // only ever points ffmpeg at a unique temp path (ConversionJob renames atomically).
    static let commonPrefix = ["-y", "-nostdin", "-v", "error"]

    // MARK: MP4

    public static func mp4Command(source: URL,
                                  destination: URL,
                                  options: ConversionOptions,
                                  audio: AudioPlan) -> [String] {
        guard case .mp4(let codec) = options.format else {
            preconditionFailure("mp4Command requires an .mp4 format")
        }
        var args = commonPrefix
        args += trimArguments(options.trim)
        args += ["-i", source.path]
        if let filters = filterChain(options: options) {
            args += ["-vf", filters]
        }
        args += ["-c:v", codec.rawValue]
        switch codec {
        case .h264, .h265:
            args += ["-preset", options.preset]
            args += ["-crf", String(options.crf ?? codec.defaultCRF)]
        case .av1:
            // B7 fix: SVT-AV1 (no -strict experimental, no -b:v 0 needed; preset 8 is
            // its speed dial, distinct from the x264/x265 named presets).
            args += ["-preset", "8"]
            args += ["-crf", String(options.crf ?? codec.defaultCRF)]
        }
        args += ["-pix_fmt", "yuv420p"] // B2 fix: SDR/compatibility promise for v1
        if codec == .h265 {
            args += ["-tag:v", "hvc1"] // B9 fix: QuickTime/Safari playback
        }
        args += audio.arguments // B6/B10 via AudioPlan
        args += ["-movflags", "+faststart"]
        if case .mp4 = options.format, let fps = options.fps {
            args += ["-r", String(fps)]
        }
        args += ["-progress", "pipe:1"]
        args.append(destination.path)
        return args
    }

    // MARK: GIF (two-pass + gifsicle)

    public static func gifPalettePass(source: URL,
                                      palette: URL,
                                      options: ConversionOptions) -> [String] {
        var args = commonPrefix
        args += trimArguments(options.trim) // B1: input-side, identical to pass 2
        args += ["-i", source.path]
        let chain = filterChain(options: options)
        let vf = chain.map { "\($0),palettegen=stats_mode=diff" } ?? "palettegen=stats_mode=diff"
        args += ["-vf", vf, "-update", "1", "-progress", "pipe:1", palette.path]
        return args
    }

    public static func gifRenderPass(source: URL,
                                     palette: URL,
                                     destination: URL,
                                     options: ConversionOptions) -> [String] {
        var args = commonPrefix
        args += trimArguments(options.trim) // B1: before the VIDEO input, not between inputs
        args += ["-i", source.path, "-i", palette.path]
        let paletteuse = "paletteuse=dither=\(options.dither):diff_mode=rectangle"
        let filterComplex: String
        if let chain = filterChain(options: options) {
            filterComplex = "[0:v]\(chain)[s]; [s][1:v]\(paletteuse)"
        } else {
            filterComplex = "[0:v][1:v]\(paletteuse)"
        }
        args += ["-filter_complex", filterComplex, "-progress", "pipe:1"]
        args.append(destination.path)
        return args
    }

    public static func gifsicleCommand(target: URL, options: ConversionOptions) -> [String] {
        var args: [String] = []
        switch options.lossy {
        case .off: break
        case .defaultLevel: args.append("--lossy")
        case .level(let n): args.append("--lossy=\(n)")
        }
        args += ["-O3", "-o", target.path, target.path]
        return args
    }
}
