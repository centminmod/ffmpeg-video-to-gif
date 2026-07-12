// M3: user-adjustable interface scale (Settings ▸ ⌘,). SwiftUI's semantic text
// styles don't scale on macOS (no Dynamic Type), so views use scaledFont(_:) —
// explicit point sizes multiplied by one persisted factor. Layout constants that
// must grow with the text (drop zone, window minimums) multiply by the same factor.

import SwiftUI

enum UIScale {
    static let key = "uiScale"
    static let defaultValue = 1.0
    /// Radio options for Settings; 4K-at-150%-scaling users land around 1.25–1.5.
    static let options: [(label: String, value: Double)] = [
        ("Default", 1.0), ("Medium (125%)", 1.25), ("Large (150%)", 1.5),
        ("Extra Large (175%)", 1.75), ("Huge (200%)", 2.0),
    ]
}

private struct ScaledFontModifier: ViewModifier {
    @AppStorage(UIScale.key) private var scale = UIScale.defaultValue
    let size: Double
    let design: Font.Design
    let monospacedDigit: Bool

    func body(content: Content) -> some View {
        let base = Font.system(size: size * scale, design: design)
        content.font(monospacedDigit ? base.monospacedDigit() : base)
    }
}

extension View {
    /// `size` is the 100%-scale point size (macOS defaults: body 13, callout 12,
    /// caption 10); the user's Settings scale multiplies it.
    func scaledFont(_ size: Double, design: Font.Design = .default,
                    monospacedDigit: Bool = false) -> some View {
        modifier(ScaledFontModifier(size: size, design: design,
                                    monospacedDigit: monospacedDigit))
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            PresetsSettingsView()
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
        }
        .scaledFont(13) // default for everything without an explicit font
    }
}

struct GeneralSettingsView: View {
    @AppStorage(UIScale.key) private var uiScale = UIScale.defaultValue

    var body: some View {
        Form {
            Picker("Text size:", selection: $uiScale) {
                ForEach(UIScale.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.radioGroup)
            .help("Interface scale factor: every font size, control padding, and "
                  + "window minimum in VidConvert is multiplied by it. It only "
                  + "affects this app's interface — never the converted videos.")
            Text("Scales all text and controls in the VidConvert window — the "
                 + "chosen factor (100–200%) multiplies every font size and "
                 + "scale-aware spacing. Made for high-DPI/scaled displays; it "
                 + "changes the app's interface only, never the video output. "
                 + "Applies immediately and is remembered across launches.")
                .scaledFont(10)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 340 * uiScale) // scaled like PresetsSettingsView, or the
                                     // labels wrap inside a 13pt-sized width
    }
}
