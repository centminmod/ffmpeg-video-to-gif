// Display-oriented ffprobe wrapper for the before/after metadata popovers. Lives in
// the app (not ConverterEngine) because it's pure presentation: the engine's MediaInfo
// keeps only the fields conversions need, while this decodes the richer stream/format
// JSON and turns it into labeled strings.

import Foundation
import ConverterEngine

struct MediaDetails: Sendable {
    var rows: [(label: String, value: String)]

    static func probe(url: URL, ffprobe: URL) throws -> MediaDetails {
        let result = try ProcessRunner().run(
            tool: ffprobe,
            arguments: ["-v", "error", "-print_format", "json",
                        "-show_format", "-show_streams", url.path],
            captureStdout: true)
        guard result.exitCode == 0, let data = result.stdoutData,
              let output = try? JSONDecoder().decode(FFprobeDisplayOutput.self, from: data)
        else {
            throw NSError(domain: "MediaDetails", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ffprobe failed" +
                    (result.stderrTail.isEmpty ? "" : ": \(result.stderrTail)")])
        }
        return MediaDetails(rows: rows(for: url, output: output))
    }

    // MARK: formatting

    private static func rows(for url: URL,
                             output: FFprobeDisplayOutput) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        rows.append(("File", url.lastPathComponent))
        if let size = output.format?.size.flatMap(Int64.init) {
            rows.append(("Size", size.formatted(.byteCount(style: .file))))
        }
        if let container = output.format?.format_long_name ?? output.format?.format_name {
            rows.append(("Container", container))
        }
        if let duration = output.format?.duration.flatMap(Double.init) {
            rows.append(("Duration", formatDuration(duration)))
        }
        if let bitRate = output.format?.bit_rate.flatMap(Double.init) {
            rows.append(("Bitrate", formatBitrate(bitRate)))
        }
        let streams = output.streams ?? []
        if let video = streams.first(where: { $0.codec_type == "video" }) {
            var parts: [String] = []
            if let codec = video.codec_name { parts.append(codec) }
            if let w = video.width, let h = video.height { parts.append("\(w)×\(h)") }
            if let fps = frameRate(video.avg_frame_rate) ?? frameRate(video.r_frame_rate) {
                parts.append(fps)
            }
            if !parts.isEmpty { rows.append(("Video", parts.joined(separator: " · "))) }
            if let pixFmt = video.pix_fmt { rows.append(("Pixel format", pixFmt)) }
        }
        if let audio = streams.first(where: { $0.codec_type == "audio" }) {
            var parts: [String] = [audio.codec_name ?? "unknown"]
            if let rate = audio.sample_rate.flatMap(Double.init) {
                let khz = rate / 1000
                parts.append(khz.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(khz)) kHz" : String(format: "%.1f kHz", khz))
            }
            if let channels = audio.channels {
                parts.append(channels == 1 ? "mono" : channels == 2 ? "stereo" : "\(channels) ch")
            }
            rows.append(("Audio", parts.joined(separator: " · ")))
        } else {
            rows.append(("Audio", "none"))
        }
        return rows
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    private static func formatBitrate(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1_000_000
            ? String(format: "%.1f Mb/s", bitsPerSecond / 1_000_000)
            : String(format: "%.0f kb/s", bitsPerSecond / 1_000)
    }

    /// "30000/1001" → "29.97 fps", "10/1" → "10 fps"; "0/0" (ffprobe's N/A) → nil.
    private static func frameRate(_ expr: String?) -> String? {
        guard let expr else { return nil }
        let parts = expr.split(separator: "/").compactMap { Double($0) }
        let fps: Double
        switch parts.count {
        case 1: fps = parts[0]
        case 2 where parts[1] > 0: fps = parts[0] / parts[1]
        default: return nil
        }
        guard fps > 0 else { return nil }
        return fps.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(fps)) fps"
            : String(format: "%.2f fps", fps)
    }
}

// Superset of the engine's FFprobeOutput — display fields only.
private struct FFprobeDisplayOutput: Decodable {
    struct Stream: Decodable {
        let codec_type: String?
        let codec_name: String?
        let width: Int?
        let height: Int?
        let pix_fmt: String?
        let avg_frame_rate: String?
        let r_frame_rate: String?
        let sample_rate: String?
        let channels: Int?
    }
    struct Format: Decodable {
        let format_name: String?
        let format_long_name: String?
        let duration: String?
        let size: String?
        let bit_rate: String?
    }
    let streams: [Stream]?
    let format: Format?
}
