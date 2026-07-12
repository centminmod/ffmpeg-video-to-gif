// Value model for one conversion. Mirrors vid2gif_pro's flags (the canonical spec in
// ../../vid2gif_func.sh) with the PRD §1 bug fixes; see FFmpegCommandBuilder for the
// per-bug annotations.

import Foundation

public enum OutputFormat: Equatable, Sendable {
    case gif
    case mp4(VideoCodec)
}

public enum VideoCodec: String, Equatable, Sendable {
    case h264 = "libx264"
    case h265 = "libx265"
    case av1 = "libsvtav1" // B7 fix: SVT-AV1, not libaom
    // M3 fast tier: Apple VideoToolbox hardware encoders. The vendored ffmpeg 8.1.2
    // arm64 build ships both, and the app is arm64-only, so constant-quality mode
    // (-q:v) is always available — the engine never uses VT bitrate mode.
    case h264VT = "h264_videotoolbox"
    case hevcVT = "hevc_videotoolbox"

    /// B5 fix: per-codec CRF defaults (script used 23 for everything).
    /// For the VideoToolbox codecs, ConversionOptions.crf is reinterpreted as the
    /// -q:v quality value (1–100, HIGHER = better — the inverse of CRF); it stays in
    /// the same storage field and the preset-editor UI relabels it per codec.
    public var defaultCRF: Int {
        switch self {
        case .h264: 23
        case .h265: 28
        case .av1: 32
        case .h264VT, .hevcVT: 50
        }
    }
}

public enum Scale: Equatable, Sendable {
    case original
    case half            // scale=iw/2:-2
    case third           // scale=iw/3:-2
    case fitWidth(Int)   // scale=W:-2
    case fitHeight(Int)  // scale=-2:H
    // B3 note: the script silently dropped H when both W and H were given. The engine
    // has no WxH case at all — the UI offers explicit fit-width/fit-height (fit-box is
    // a v1.x addition), so the ambiguity cannot arise.

    /// B11 fix (found by panel review, reproduced against the vendored ffmpeg):
    /// the script's `scale=iw/2:-2` only forces the HEIGHT even, so a 2-mod-4
    /// source like 854×480 halves to an odd 427 width and libx264/libx265 with
    /// yuv420p hard-fail ("width not divisible by 2"). MP4 outputs therefore
    /// round the free axis down to even; GIF has no such constraint and keeps
    /// the script-exact filters for golden parity.
    func filter(evenDimensions: Bool) -> String? {
        switch self {
        case .original: nil
        case .half: evenDimensions ? "scale=trunc(iw/4)*2:-2" : "scale=iw/2:-2"
        case .third: evenDimensions ? "scale=trunc(iw/6)*2:-2" : "scale=iw/3:-2"
        case .fitWidth(let w): "scale=\(evenDimensions ? w & ~1 : w):-2"
        case .fitHeight(let h): "scale=-2:\(evenDimensions ? h & ~1 : h)"
        }
    }
}

public struct Trim: Equatable, Sendable {
    /// ffmpeg time expressions ("12", "00:01:30", "1:30.5"), validated at the UI layer.
    public var start: String?
    public var end: String?
    public init(start: String? = nil, end: String? = nil) {
        self.start = start
        self.end = end
    }
    public var isEmpty: Bool { start == nil && end == nil }
}

public enum GifLossy: Equatable, Sendable {
    case off
    case defaultLevel    // gifsicle --lossy
    case level(Int)      // gifsicle --lossy=N
}

public struct ConversionOptions: Equatable, Sendable {
    public var format: OutputFormat
    public var scale: Scale
    public var fps: Int?          // required-with-default for GIF (10), optional for MP4
    public var crf: Int?          // nil → codec default (B5)
    public var preset: String     // x264/x265 preset
    public var trim: Trim
    public var dither: String     // paletteuse dither algo
    public var lossy: GifLossy
    public var optimizeGif: Bool  // gifsicle -O3 pass

    public init(format: OutputFormat,
                scale: Scale = .original,
                fps: Int? = nil,
                crf: Int? = nil,
                preset: String = "medium",
                trim: Trim = Trim(),
                dither: String = "sierra2_4a",
                lossy: GifLossy = .off,
                optimizeGif: Bool = true) {
        self.format = format
        self.scale = scale
        self.fps = fps
        self.crf = crf
        self.preset = preset
        self.trim = trim
        self.dither = dither
        self.lossy = lossy
        self.optimizeGif = optimizeGif
    }
}

/// The shipped presets — the first five are exact ports of the Automator wrappers in
/// ../../automator-wrappers/ (same CRFs, scales, and filename suffixes); gifFull is
/// new in the app (canonical bare-run defaults, no wrapper existed).
public struct Preset: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let options: ConversionOptions
    /// Appended to the source basename, e.g. "-h264_crf33" → "clip-h264_crf33.mp4".
    public let filenameSuffix: String
    public let fileExtension: String

    /// Public memberwise init: the app layer constructs edited/custom presets with it.
    public init(id: String, displayName: String, options: ConversionOptions,
                filenameSuffix: String, fileExtension: String) {
        self.id = id
        self.displayName = displayName
        self.options = options
        self.filenameSuffix = filenameSuffix
        self.fileExtension = fileExtension
    }

    public static let mp4H264 = Preset(
        id: "mp4-h264", displayName: "MP4 · Compatible (H.264)",
        options: ConversionOptions(format: .mp4(.h264), crf: 33),
        filenameSuffix: "-h264_crf33", fileExtension: "mp4")

    public static let mp4H264Half = Preset(
        id: "mp4-h264-half", displayName: "MP4 · Compatible (H.264, ½ size)",
        options: ConversionOptions(format: .mp4(.h264), scale: .half, crf: 29),
        filenameSuffix: "-h264_half_size_crf29", fileExtension: "mp4")

    public static let mp4H265 = Preset(
        id: "mp4-h265", displayName: "MP4 · Smaller (H.265)",
        options: ConversionOptions(format: .mp4(.h265), crf: 35),
        filenameSuffix: "-h265_crf35", fileExtension: "mp4")

    public static let mp4H265Half = Preset(
        id: "mp4-h265-half", displayName: "MP4 · Smaller (H.265, ½ size)",
        options: ConversionOptions(format: .mp4(.h265), scale: .half, crf: 31),
        filenameSuffix: "-h265_half_size_crf31", fileExtension: "mp4")

    public static let gifSmall = Preset(
        id: "gif-small", displayName: "GIF · Small (⅓ size)",
        options: ConversionOptions(format: .gif, scale: .third, fps: 6,
                                   dither: "bayer", lossy: .defaultLevel),
        filenameSuffix: "-third_size", fileExtension: "gif")

    /// No Automator wrapper existed for this one — it mirrors a bare `vid2gif_pro`
    /// run: original resolution, default_gif_fps=10, default dither, no lossy.
    public static let gifFull = Preset(
        id: "gif-full", displayName: "GIF · Full size",
        options: ConversionOptions(format: .gif, fps: 10),
        filenameSuffix: "-full_size", fileExtension: "gif")

    /// M3 addition, also with no wrapper ancestry: SVT-AV1 at its codec-default
    /// CRF 32 (B5/B7) for the smallest files, at the cost of encode speed.
    public static let mp4AV1 = Preset(
        id: "mp4-av1", displayName: "MP4 · Smallest (AV1)",
        options: ConversionOptions(format: .mp4(.av1)),
        filenameSuffix: "-av1_crf32", fileExtension: "mp4")

    /// M3 VideoToolbox fast tier (no wrapper ancestry): hardware encode trades size
    /// for speed. Codec-default -q:v 50 (see VideoCodec.defaultCRF).
    public static let mp4H264VT = Preset(
        id: "mp4-h264-vt", displayName: "MP4 · Fast (H.264 hardware)",
        options: ConversionOptions(format: .mp4(.h264VT)),
        filenameSuffix: "-h264_vt_q50", fileExtension: "mp4")

    public static let mp4HEVCVT = Preset(
        id: "mp4-h265-vt", displayName: "MP4 · Fast (H.265 hardware)",
        options: ConversionOptions(format: .mp4(.hevcVT)),
        filenameSuffix: "-h265_vt_q50", fileExtension: "mp4")

    public static let all: [Preset] = [mp4H264, mp4H264Half, mp4H265, mp4H265Half,
                                       gifSmall, gifFull, mp4AV1,
                                       mp4H264VT, mp4HEVCVT]
}
