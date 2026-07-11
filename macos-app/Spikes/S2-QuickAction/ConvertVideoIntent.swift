// S2 Vehicle B — App Intent + AppShortcutsProvider.
// Add to the QuickActionSpike APP target (not the extension).
// Spike scope: after creating a Shortcut from this intent and ticking
// "Use as Quick Action" ▸ Finder, does it appear in the same Finder menu as
// Vehicle A, and with how much user assembly?

import AppIntents

struct ConvertVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Convert Video (Spike)"
    static let description = IntentDescription(
        "M0a spike: verifies whether an App Intent taking movie files can surface as a Finder Quick Action.")
    static let openAppWhenRun = true

    @Parameter(title: "Videos", supportedContentTypes: [.movie])
    var videos: [IntentFile]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let names = videos.map(\.filename).joined(separator: ", ")
        return .result(dialog: "Received \(videos.count) file(s): \(names)")
    }
}

struct SpikeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConvertVideoIntent(),
                    phrases: ["Convert video with \(.applicationName)"],
                    shortTitle: "Convert Video",
                    systemImageName: "film")
    }
}
