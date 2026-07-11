// B10 fix: parses ffprobe's JSON and requires an actual audio-stream object — the
// script trusted ffprobe's exit status, which is 0 for any readable file, so every
// silent video was treated as having audio.

import Foundation

public struct MediaInfo: Equatable, Sendable {
    public var durationSeconds: Double?  // nil when ffprobe reports N/A (live/odd containers)
    public var width: Int?
    public var height: Int?
    public var hasAudio: Bool
    public var audioCodec: String?       // e.g. "aac", "pcm_s16le"

    public var audioPlan: AudioPlan {
        .forSource(hasAudio: hasAudio, audioCodec: audioCodec)
    }

    /// Duration of the segment a Trim leaves, for progress math (PRD §5: progress =
    /// out_time ÷ *effective* duration).
    public func effectiveDuration(trim: Trim) -> Double? {
        guard let total = durationSeconds else { return nil }
        let start = trim.start.flatMap(MediaProbe.seconds(fromTimeExpression:)) ?? 0
        let end = trim.end.flatMap(MediaProbe.seconds(fromTimeExpression:)) ?? total
        let effective = min(end, total) - start
        return effective > 0 ? effective : nil
    }
}

public enum MediaProbeError: Error, Equatable {
    case ffprobeFailed(exitCode: Int32, stderr: String)
    case unparseableOutput
    case cancelled
}

public enum MediaProbe {

    public static func arguments(for source: URL) -> [String] {
        ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", source.path]
    }

    /// Runs ffprobe synchronously (fast — metadata only) and parses the result.
    /// Goes through ProcessRunner so both pipes drain concurrently (no pipe-buffer
    /// deadlock on chatty stderr) and the caller can register `runner` for cancellation.
    public static func probe(source: URL, ffprobe: URL,
                             runner: ProcessRunner = ProcessRunner()) throws -> MediaInfo {
        let result: ProcessResult
        do {
            result = try runner.run(tool: ffprobe, arguments: arguments(for: source),
                                    captureStdout: true)
        } catch {
            throw MediaProbeError.ffprobeFailed(exitCode: -1,
                                                stderr: error.localizedDescription)
        }
        if result.wasCancelled { throw MediaProbeError.cancelled }
        guard result.exitCode == 0 else {
            throw MediaProbeError.ffprobeFailed(exitCode: result.exitCode,
                                                stderr: result.stderrTail)
        }
        return try parse(json: result.stdoutData ?? Data())
    }

    // MARK: parsing (separated for unit testing without ffprobe)

    struct FFprobeOutput: Decodable {
        struct Stream: Decodable {
            let codec_type: String?
            let codec_name: String?
            let width: Int?
            let height: Int?
        }
        struct Format: Decodable {
            let duration: String?
        }
        let streams: [Stream]?
        let format: Format?
    }

    public static func parse(json: Data) throws -> MediaInfo {
        guard let output = try? JSONDecoder().decode(FFprobeOutput.self, from: json) else {
            throw MediaProbeError.unparseableOutput
        }
        let streams = output.streams ?? []
        let video = streams.first { $0.codec_type == "video" }
        let audio = streams.first { $0.codec_type == "audio" }
        // "N/A" (or absent) duration must map to nil, not 0 (PRD §5 progress spec).
        let duration = output.format?.duration.flatMap(Double.init)
        return MediaInfo(durationSeconds: duration,
                         width: video?.width,
                         height: video?.height,
                         hasAudio: audio != nil,
                         audioCodec: audio?.codec_name)
    }

    /// "90", "1:30", "01:02:03.5" → seconds. Mirrors ffmpeg time-expression rules
    /// closely enough for progress math (NOT used to build commands — the raw string
    /// is passed to ffmpeg untouched).
    public static func seconds(fromTimeExpression expr: String) -> Double? {
        let parts = expr.split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }
}
