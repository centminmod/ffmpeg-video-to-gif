// M3 preset editor model. Preset.all stays the source of truth for built-in
// identity; this store layers user edits on top: OVERRIDES of built-in parameters
// (keyed by preset id) plus fully CUSTOM presets. Both persist as JSON blobs in
// UserDefaults and are folded into `effectivePresets`, which every consumer
// (chips, queue intake, Quick Action handoffs) resolves through.

import Foundation
import ConverterEngine

/// The codec/format choice exposed to the editor — one case per shipped encode
/// path. Raw values are persisted, so they must stay stable.
enum PresetFormat: String, Codable, CaseIterable, Identifiable {
    case gif, h264, h265, av1, h264VT, hevcVT

    var id: String { rawValue }

    init(options: ConversionOptions) {
        switch options.format {
        case .gif: self = .gif
        case .mp4(.h264): self = .h264
        case .mp4(.h265): self = .h265
        case .mp4(.av1): self = .av1
        case .mp4(.h264VT): self = .h264VT
        case .mp4(.hevcVT): self = .hevcVT
        }
    }

    var label: String {
        switch self {
        case .gif: "GIF"
        case .h264: "H.264"
        case .h265: "H.265"
        case .av1: "AV1"
        case .h264VT: "H.264 hardware"
        case .hevcVT: "H.265 hardware"
        }
    }

    var outputFormat: OutputFormat {
        switch self {
        case .gif: .gif
        case .h264: .mp4(.h264)
        case .h265: .mp4(.h265)
        case .av1: .mp4(.av1)
        case .h264VT: .mp4(.h264VT)
        case .hevcVT: .mp4(.hevcVT)
        }
    }

    var fileExtension: String { self == .gif ? "gif" : "mp4" }

    /// x264/x265 honor the named -preset speed dial; AV1 is pinned to preset 8 in
    /// the engine (B7) and VideoToolbox has no equivalent.
    var usesSpeedPreset: Bool { self == .h264 || self == .h265 }

    var isVideoToolbox: Bool { self == .h264VT || self == .hevcVT }

    /// ConversionOptions.crf is CRF for the software codecs but the -q:v 1–100
    /// constant-quality value for VideoToolbox (see VideoCodec.defaultCRF).
    /// Per-codec ceilings (verified against the vendored ffmpeg): libx265 REJECTS
    /// CRF > 51 at encode time; x264 and SVT-AV1 accept up to 63. options()
    /// clamps to this range, which also repairs already-persisted values.
    var qualityRange: ClosedRange<Int> {
        switch self {
        case .h264VT, .hevcVT: 1...100
        case .h265: 0...51
        case .gif, .h264, .av1: 0...63
        }
    }

    var qualityLabel: String {
        isVideoToolbox ? "Quality (1–100, higher = better)" : "CRF (lower = better)"
    }

    var defaultQuality: Int {
        switch self {
        case .gif: 0 // GIF has no quality dial; field is unused/hidden
        case .h264: VideoCodec.h264.defaultCRF
        case .h265: VideoCodec.h265.defaultCRF
        case .av1: VideoCodec.av1.defaultCRF
        case .h264VT: VideoCodec.h264VT.defaultCRF
        case .hevcVT: VideoCodec.hevcVT.defaultCRF
        }
    }
}

/// Flat Codable snapshot of the editable "quality and conversion parameters".
/// The engine's ConversionOptions/Scale/GifLossy are deliberately not Codable —
/// this app-layer struct is the persistence boundary and round-trips to them.
struct PresetParameters: Codable, Equatable {
    enum ScaleMode: String, Codable, CaseIterable { case original, half, third, fitWidth, fitHeight }
    enum LossyMode: String, Codable, CaseIterable { case off, defaultLevel, level }

    var quality: Int          // CRF, or -q:v for VideoToolbox (see PresetFormat)
    var fps: Int?             // nil = keep source rate (MP4); GIF always has one
    var scaleMode: ScaleMode
    var scaleValue: Int       // fitWidth/fitHeight pixel target
    var speedPreset: String   // x264/x265 -preset name
    var dither: String        // GIF paletteuse algorithm
    var lossyMode: LossyMode
    var lossyLevel: Int       // gifsicle --lossy=N when lossyMode == .level
    var optimizeGif: Bool

    static let speedPresets = ["ultrafast", "superfast", "veryfast", "faster",
                               "fast", "medium", "slow", "slower", "veryslow"]

    /// Fresh-custom defaults for `format`.
    init(format: PresetFormat) {
        quality = format.defaultQuality
        fps = format == .gif ? 10 : nil // engine's GIF default (script default_gif_fps)
        scaleMode = .original
        scaleValue = 720
        speedPreset = "medium"
        dither = "sierra2_4a"
        lossyMode = .off
        lossyLevel = 20 // gifsicle's implied --lossy level, seeds the .level stepper
        optimizeGif = true
    }

    /// Snapshot of a shipped preset's options — the editor's baseline values.
    init(options: ConversionOptions, format: PresetFormat) {
        self.init(format: format)
        quality = options.crf ?? format.defaultQuality
        fps = options.fps
        switch options.scale {
        case .original: scaleMode = .original
        case .half: scaleMode = .half
        case .third: scaleMode = .third
        case .fitWidth(let w): scaleMode = .fitWidth; scaleValue = w
        case .fitHeight(let h): scaleMode = .fitHeight; scaleValue = h
        }
        speedPreset = options.preset
        dither = options.dither
        switch options.lossy {
        case .off: lossyMode = .off
        case .defaultLevel: lossyMode = .defaultLevel
        case .level(let n): lossyMode = .level; lossyLevel = n
        }
        optimizeGif = options.optimizeGif
    }

    /// Round-trip back to engine options. Trim is not part of preset editing
    /// (it is a per-file concern, wired separately).
    func options(format: PresetFormat) -> ConversionOptions {
        let scale: Scale = switch scaleMode {
        case .original: .original
        case .half: .half
        case .third: .third
        // yuv420p needs even dimensions; -2 handles the free axis, so round the
        // fixed one down to even for MP4 (GIF has no such constraint).
        case .fitWidth: .fitWidth(clampedScaleValue(evenFor: format))
        case .fitHeight: .fitHeight(clampedScaleValue(evenFor: format))
        }
        let lossy: GifLossy = switch lossyMode {
        case .off: .off
        case .defaultLevel: .defaultLevel
        case .level: .level(lossyLevel)
        }
        // Clamp persisted values (hand-edited defaults, older app versions) to the
        // ranges the editor enforces.
        let clampedQuality = min(max(quality, format.qualityRange.lowerBound),
                                 format.qualityRange.upperBound)
        return ConversionOptions(
            format: format.outputFormat,
            scale: scale,
            fps: format == .gif ? (fps ?? 10) : fps,
            crf: format == .gif ? nil : clampedQuality,
            preset: speedPreset,
            dither: dither,
            lossy: lossy,
            optimizeGif: optimizeGif)
    }

    private func clampedScaleValue(evenFor format: PresetFormat) -> Int {
        let floored = max(2, scaleValue)
        return format == .gif ? floored : floored & ~1
    }
}

/// A user-created preset: name + format + parameters.
struct CustomPreset: Codable, Equatable, Identifiable {
    var id: String            // "custom-<UUID>", never collides with built-in ids
    var name: String
    var format: PresetFormat
    var parameters: PresetParameters
}

@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published private(set) var overrides: [String: PresetParameters]
    @Published private(set) var customs: [CustomPreset]

    private static let overridesKey = "presetOverrides"
    private static let customsKey = "customPresets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overrides = Self.decode([String: PresetParameters].self,
                                key: Self.overridesKey, from: defaults) ?? [:]
        customs = Self.decode([CustomPreset].self,
                              key: Self.customsKey, from: defaults) ?? []
    }

    private let defaults: UserDefaults

    private static func decode<T: Decodable>(_ type: T.Type, key: String,
                                             from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(overrides), forKey: Self.overridesKey)
        defaults.set(try? JSONEncoder().encode(customs), forKey: Self.customsKey)
    }

    // MARK: resolution

    /// Built-ins with overrides applied, then customs — what the whole app uses.
    var effectivePresets: [Preset] {
        Preset.all.map { builtin in
            guard let parameters = overrides[builtin.id] else { return builtin }
            let format = PresetFormat(options: builtin.options)
            return Preset(id: builtin.id,
                          displayName: builtin.displayName,
                          options: parameters.options(format: format),
                          filenameSuffix: Self.suffix(builtin: builtin,
                                                      parameters: parameters,
                                                      format: format),
                          fileExtension: builtin.fileExtension)
        } + customs.map { custom in
            Preset(id: custom.id,
                   displayName: custom.name,
                   options: custom.parameters.options(format: custom.format),
                   filenameSuffix: "-" + Self.slug(custom.name),
                   fileExtension: custom.format.fileExtension)
        }
    }

    /// Preset lookup for chips selection and Quick Action handoffs — resolves over
    /// effectivePresets so an edited built-in converts with its edited values.
    func preset(withID id: String) -> Preset? {
        effectivePresets.first { $0.id == id }
    }

    /// Every shipped MP4 suffix ends in its crf/q number ("-h264_crf33",
    /// "-h265_vt_q50"); when the quality was edited, swap that trailing number so
    /// the output filename doesn't lie. GIF suffixes ("-third_size") carry no
    /// number and are kept as shipped.
    private static func suffix(builtin: Preset, parameters: PresetParameters,
                               format: PresetFormat) -> String {
        let shipped = builtin.filenameSuffix
        guard format != .gif,
              parameters.quality != PresetParameters(options: builtin.options,
                                                     format: format).quality,
              let digits = shipped.range(of: "[0-9]+$", options: .regularExpression)
        else { return shipped }
        return shipped.replacingCharacters(in: digits, with: String(parameters.quality))
    }

    /// "My Preset!" → "my-preset": lowercase ASCII alphanumerics, runs of anything
    /// else collapse to a single dash.
    static func slug(_ name: String) -> String {
        var slug = ""
        for scalar in name.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty && slug.last != "-" {
                slug.append("-")
            }
        }
        while slug.last == "-" { slug.removeLast() }
        return slug.isEmpty ? "custom" : slug
    }

    // MARK: built-in overrides

    func hasOverride(id: String) -> Bool { overrides[id] != nil }

    func setOverride(_ parameters: PresetParameters, for builtin: Preset) {
        // Editing back to the shipped values IS a revert — keeps "(edited)" honest.
        let shipped = PresetParameters(options: builtin.options,
                                       format: PresetFormat(options: builtin.options))
        overrides[builtin.id] = parameters == shipped ? nil : parameters
        persist()
    }

    func revertOverride(id: String) {
        overrides[id] = nil
        persist()
    }

    // MARK: custom presets

    /// Appends a fresh custom preset and returns its id (for list selection).
    func addCustom() -> String {
        let custom = CustomPreset(id: "custom-\(UUID().uuidString)",
                                  name: "New Preset",
                                  format: .h264,
                                  parameters: PresetParameters(format: .h264))
        customs.append(custom)
        persist()
        return custom.id
    }

    func updateCustom(_ preset: CustomPreset) {
        guard let index = customs.firstIndex(where: { $0.id == preset.id }) else { return }
        customs[index] = preset
        persist()
    }

    func removeCustom(id: String) {
        customs.removeAll { $0.id == id }
        persist()
    }
}
