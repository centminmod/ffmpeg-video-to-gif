// Settings ▸ Presets tab: master list (built-ins, then customs) with +/− footer,
// detail form editing the PresetStore parameters. Built-ins keep their identity —
// edits become overrides with a "Revert to Default" escape hatch; only customs
// can be added/deleted.

import SwiftUI
import ConverterEngine

struct PresetsSettingsView: View {
    @EnvironmentObject private var store: PresetStore
    @AppStorage(UIScale.key) private var uiScale = UIScale.defaultValue
    @State private var selectedID: String?

    var body: some View {
        HStack(spacing: 0) {
            masterColumn
                .frame(width: 210 * uiScale)
            Divider()
            // The detail column scrolls so capping the tab height (below) can't
            // clip the form or the Revert button.
            ScrollView {
                detail
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        // Cap the height: the Settings window is not user-resizable, and at 200%
        // scale an uncapped 860pt tab (plus title/tab chrome) overflows
        // 900pt-class displays such as 1440x900.
        .frame(width: 600 * uiScale,
               height: min(430 * uiScale,
                           (NSScreen.main?.visibleFrame.height ?? 900) - 120))
        .onAppear {
            if selectedID == nil { selectedID = Preset.all.first?.id }
        }
    }

    // MARK: master list

    private var masterColumn: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                Section {
                    ForEach(Preset.all) { preset in
                        // "(edited)" marks an override here in the editor only —
                        // the main-window chip keeps the plain name.
                        Text(store.hasOverride(id: preset.id)
                             ? "\(preset.displayName) (edited)" : preset.displayName)
                            .scaledFont(12)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(preset.id)
                    }
                } header: {
                    Text("Built-in").scaledFont(10)
                }
                if !store.customs.isEmpty {
                    Section {
                        ForEach(store.customs) { custom in
                            Text(custom.name)
                                .scaledFont(12)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .tag(custom.id)
                        }
                    } header: {
                        Text("Custom").scaledFont(10)
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack(spacing: 8) {
                Button("Add custom preset", systemImage: "plus") {
                    selectedID = store.addCustom()
                }
                .help("Adds a new custom preset (your own name, format, and "
                      + "quality/conversion parameters). Customs appear as chips "
                      + "in the main window; Finder Quick Actions exist for the "
                      + "built-in presets only.")
                Button("Delete custom preset", systemImage: "minus") {
                    removeSelectedCustom()
                }
                .disabled(!selectionIsCustom)
                .help("Deletes the selected custom preset. Built-in presets can't "
                      + "be deleted — edit them and use Revert to Default instead.")
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .scaledFont(12)
            .padding(6)
        }
    }

    private var selectionIsCustom: Bool {
        selectedID.map { id in store.customs.contains { $0.id == id } } ?? false
    }

    private func removeSelectedCustom() {
        guard let id = selectedID, selectionIsCustom else { return }
        store.removeCustom(id: id)
        selectedID = Preset.all.first?.id
    }

    // MARK: detail

    @ViewBuilder private var detail: some View {
        if let id = selectedID, let builtin = Preset.all.first(where: { $0.id == id }) {
            BuiltinPresetDetail(builtin: builtin)
        } else if let id = selectedID,
                  let custom = store.customs.first(where: { $0.id == id }) {
            CustomPresetDetail(custom: customBinding(for: custom))
        } else {
            Text("Select a preset")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The get re-resolves by id (not index) so a deletion mid-frame can't crash;
    /// updateCustom no-ops for unknown ids.
    private func customBinding(for custom: CustomPreset) -> Binding<CustomPreset> {
        Binding(
            get: { store.customs.first { $0.id == custom.id } ?? custom },
            set: { store.updateCustom($0) })
    }
}

// MARK: - built-in detail

private struct BuiltinPresetDetail: View {
    let builtin: Preset // the SHIPPED definition (baseline for the override diff)
    @EnvironmentObject private var store: PresetStore

    private var format: PresetFormat { PresetFormat(options: builtin.options) }

    /// Reads override-or-shipped; every write goes through setOverride, which
    /// drops the override again if the values match the shipped ones.
    private var parameters: Binding<PresetParameters> {
        Binding(
            get: { store.overrides[builtin.id]
                   ?? PresetParameters(options: builtin.options, format: format) },
            set: { store.setOverride($0, for: builtin) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(builtin.displayName)
                    .fontWeight(.semibold)
                Text("Edits to this built-in preset apply everywhere it is used — "
                     + "the window chips and its Finder Quick Action. An edited "
                     + "preset shows “(edited)” in the list and offers Revert to "
                     + "Default; the output filename suffix follows the edited "
                     + "quality value.")
                    .scaledFont(10)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ParameterForm(format: format, parameters: parameters)
            if store.hasOverride(id: builtin.id) {
                Button("Revert to Default") { store.revertOverride(id: builtin.id) }
                    .help("Discards your edits and restores this preset's shipped "
                          + "values (the override is deleted; the shipped defaults "
                          + "are never modified).")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

// MARK: - custom detail

private struct CustomPresetDetail: View {
    @Binding var custom: CustomPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Leading VStack, not Form — same left-alignment rationale as ParameterForm.
            VStack(alignment: .leading, spacing: 12) {
                HelpRow("Shown on the preset's chip in the main window; also used, "
                        + "lowercased-and-dashed, as the output filename suffix — "
                        + "“My GIF” saves clip-my-gif.gif next to the original.") {
                    TextField("Name:", text: $custom.name)
                        .frame(maxWidth: 320)
                }
                HelpRow("Output format and encoder: H.264 (ffmpeg libx264) plays "
                        + "everywhere; H.265 (libx265) is ~30% smaller; AV1 "
                        + "(SVT-AV1) is smallest but slow to encode; the hardware "
                        + "variants use Apple VideoToolbox — much faster, larger "
                        + "files; GIF renders a two-pass palette GIF.") {
                    Picker("Format:", selection: $custom.format) {
                        ForEach(PresetFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .fixedSize()
                }
            }
            ParameterForm(format: custom.format, parameters: $custom.parameters)
            Spacer(minLength: 0)
        }
        .padding(16)
        .onChange(of: custom.format) { _, newFormat in
            // The quality dial changes meaning per codec (CRF vs VT -q:v), so
            // re-seed its default; GIF requires an fps (engine default 10), while
            // leaving GIF drops it — an MP4 shouldn't inherit the 10fps cap.
            custom.parameters.quality = newFormat.defaultQuality
            custom.parameters.fps = newFormat == .gif ? (custom.parameters.fps ?? 10) : nil
        }
    }
}

// MARK: - help-note plumbing

/// A form row with a descriptive footnote: what the setting does and which
/// engine/ffmpeg/gifsicle parameter it drives. The same text doubles as the
/// hover tooltip on the control itself.
private struct HelpRow<Content: View>: View {
    let note: String
    let content: Content

    init(_ note: String, @ViewBuilder content: () -> Content) {
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            content.help(note)
            Text(note)
                .scaledFont(10)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - shared parameter form

private struct ParameterForm: View {
    let format: PresetFormat
    @Binding var parameters: PresetParameters

    private typealias ScaleMode = PresetParameters.ScaleMode
    private typealias LossyMode = PresetParameters.LossyMode

    /// Per-codec explanation of the quality dial — the same stored value feeds
    /// `-crf` for the software codecs but `-q:v` for VideoToolbox.
    private var qualityCaption: String {
        format.isVideoToolbox
            ? "Hardware constant quality (ffmpeg -q:v, 1–100): HIGHER = better "
              + "quality and a larger file. VideoToolbox encodes are much faster "
              + "than software but produce larger files at comparable quality."
            : "Constant Rate Factor (ffmpeg -crf): LOWER = better quality and a "
              + "larger file. Roughly: 18 near-lossless, 23–28 good, 33+ small. "
              + (format == .h265 ? "x265 accepts 0–51."
                                 : "Accepted range 0–63.")
    }

    var body: some View {
        // A leading-aligned VStack, not a Form: Form's trailing-aligned label
        // column centers the control block and staggers the left edges (user
        // request: settings variables left-aligned with their help notes).
        VStack(alignment: .leading, spacing: 12) {
            if format != .gif {
                HelpRow(qualityCaption) {
                    Stepper(value: $parameters.quality, in: format.qualityRange) {
                        Text("\(format.qualityLabel): \(parameters.quality)")
                    }
                    .fixedSize()
                }
            }
            if format.usesSpeedPreset {
                HelpRow("Encoder effort (ffmpeg -preset, ultrafast → veryslow): "
                        + "slower presets compress better, so the file gets smaller "
                        + "at the SAME quality — this trades encode time, not quality.") {
                    Picker("Encoder speed:", selection: $parameters.speedPreset) {
                        ForEach(PresetParameters.speedPresets, id: \.self) { Text($0) }
                    }
                    .fixedSize()
                }
            }
            HelpRow("Output resolution (ffmpeg scale filter): Original keeps the "
                    + "source size; Half/Third divide it; Fit width/height resizes "
                    + "to a pixel target, keeping the aspect ratio. MP4 dimensions "
                    + "are rounded to even numbers (encoder requirement).") {
                Picker("Scale:", selection: $parameters.scaleMode) {
                    Text("Original size").tag(ScaleMode.original)
                    Text("Half (½)").tag(ScaleMode.half)
                    Text("Third (⅓)").tag(ScaleMode.third)
                    Text("Fit width").tag(ScaleMode.fitWidth)
                    Text("Fit height").tag(ScaleMode.fitHeight)
                }
                .fixedSize()
            }
            if parameters.scaleMode == .fitWidth || parameters.scaleMode == .fitHeight {
                HelpRow("Pixel target for the fixed axis; the other axis follows "
                        + "the source aspect ratio automatically.") {
                    TextField(parameters.scaleMode == .fitWidth ? "Width (px):" : "Height (px):",
                              value: $parameters.scaleValue, format: .number)
                        .frame(width: 160)
                }
            }
            fpsControls
            if format == .gif { gifControls }
        }
    }

    @ViewBuilder private var fpsControls: some View {
        if format == .gif {
            // GIF always renders at an explicit fps (script default_gif_fps=10).
            HelpRow("GIF frames per second (ffmpeg fps filter): lower = smaller "
                    + "file but choppier motion. 10 is the classic screen-recording "
                    + "default; 5–8 shrinks files further.") {
                Stepper(value: gifFPS, in: 1...60) {
                    Text("Frame rate: \(gifFPS.wrappedValue) fps")
                }
                .fixedSize()
            }
        } else {
            HelpRow("When on, caps the output frame rate (ffmpeg -r), dropping "
                    + "frames above the cap to shrink the file. Off keeps the "
                    + "source frame rate untouched.") {
                Toggle("Limit frame rate", isOn: limitsFrameRate)
            }
            if parameters.fps != nil {
                HelpRow("Maximum output frames per second — e.g. 30 halves a 60fps "
                        + "screen recording's frame count.") {
                    Stepper(value: mp4FPS, in: 1...60) {
                        Text("Frame rate: \(mp4FPS.wrappedValue) fps")
                    }
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder private var gifControls: some View {
        HelpRow("How colors outside the 256-color GIF palette are approximated "
                + "(ffmpeg paletteuse dither): sierra2_4a = best quality; bayer = "
                + "smaller files with a fine crosshatch pattern; floyd_steinberg = "
                + "classic grain; none = flat color bands, smallest file.") {
            Picker("Dither:", selection: $parameters.dither) {
                Text("sierra2_4a (default)").tag("sierra2_4a")
                Text("bayer").tag("bayer")
                Text("floyd_steinberg").tag("floyd_steinberg")
                Text("none").tag("none")
            }
            .fixedSize()
        }
        HelpRow("Lossy recompression (gifsicle --lossy): allows small visual "
                + "artifacts to cut GIF size significantly. Off = pixel-exact; "
                + "Default = gifsicle's built-in level; Custom = pick the strength "
                + "yourself.") {
            Picker("Lossy (gifsicle):", selection: $parameters.lossyMode) {
                Text("Off").tag(LossyMode.off)
                Text("Default").tag(LossyMode.defaultLevel)
                Text("Custom level").tag(LossyMode.level)
            }
            .fixedSize()
        }
        if parameters.lossyMode == .level {
            HelpRow("gifsicle --lossy=N (1–200): higher = smaller file, more "
                    + "artifacts. 20–80 is the useful range for most clips.") {
                Stepper(value: $parameters.lossyLevel, in: 1...200) {
                    Text("Lossy level: \(parameters.lossyLevel)")
                }
                .fixedSize()
            }
        }
        HelpRow("Runs gifsicle -O3 after rendering — lossless re-optimization of "
                + "frames and palettes (safe, recommended). If gifsicle fails, the "
                + "unoptimized GIF is kept.") {
            Toggle("Optimize with gifsicle (-O3)", isOn: $parameters.optimizeGif)
        }
    }

    // MARK: fps bindings (fps is Optional in the model)

    private var gifFPS: Binding<Int> {
        Binding(get: { parameters.fps ?? 10 }, set: { parameters.fps = $0 })
    }

    private var mp4FPS: Binding<Int> {
        Binding(get: { parameters.fps ?? 30 }, set: { parameters.fps = $0 })
    }

    private var limitsFrameRate: Binding<Bool> {
        Binding(get: { parameters.fps != nil },
                set: { parameters.fps = $0 ? 30 : nil }) // 30 seeds the stepper
    }
}
