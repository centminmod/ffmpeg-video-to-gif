// Locates the ffmpeg/ffprobe/gifsicle binaries. The shipped app uses vendored
// copies (Vendor/ → Contents/Helpers); during development we fall back to Homebrew
// so the engine and its integration tests run before the static binaries are pinned.

import Foundation

public struct Tools: Sendable {
    public var ffmpeg: URL
    public var ffprobe: URL
    public var gifsicle: URL

    public init(ffmpeg: URL, ffprobe: URL, gifsicle: URL) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.gifsicle = gifsicle
    }

    /// Bundled helpers (Phase 1 posture: vendored arm64 binaries in Contents/Helpers).
    public static func bundled(in bundle: Bundle = .main) -> Tools? {
        let helpers = bundle.bundleURL.appendingPathComponent("Contents/Helpers")
        let tools = Tools(ffmpeg: helpers.appendingPathComponent("ffmpeg"),
                          ffprobe: helpers.appendingPathComponent("ffprobe"),
                          gifsicle: helpers.appendingPathComponent("gifsicle"))
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: tools.ffmpeg.path),
              fm.isExecutableFile(atPath: tools.ffprobe.path),
              fm.isExecutableFile(atPath: tools.gifsicle.path) else { return nil }
        return tools
    }

    /// Development fallback: well-known install locations (no PATH walking).
    public static func development() -> Tools? {
        func find(_ name: String) -> URL? {
            for dir in ["/opt/homebrew/bin", "/usr/local/bin"] {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
            return nil
        }
        guard let ffmpeg = find("ffmpeg"), let ffprobe = find("ffprobe"),
              let gifsicle = find("gifsicle") else { return nil }
        return Tools(ffmpeg: ffmpeg, ffprobe: ffprobe, gifsicle: gifsicle)
    }

    public static func locate() -> Tools? {
        bundled() ?? development()
    }
}
