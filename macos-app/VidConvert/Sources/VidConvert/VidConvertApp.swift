// M1 app shell. Single window; confirm-on-quit while conversions are active (PRD §5.6).

import SwiftUI
import ConverterEngine

@main
struct VidConvertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("VidConvert", id: "main") {
            ContentView()
                .environmentObject(QueueModel.shared)
                .frame(minWidth: 520, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Intake for the Finder Quick Actions (M2) and any other LaunchServices open.
    /// vidconvert://convert?preset=<id>&file=<path>… queues with the preset the user
    /// picked in the Finder menu; plain file URLs (Dock drop, "Open With") queue with
    /// the preset currently selected in the window — same as a drop.
    func application(_ application: NSApplication, open urls: [URL]) {
        var files: [URL] = []
        for url in urls {
            if url.scheme == "vidconvert",
               let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                let presetID = items.first { $0.name == "preset" }?.value
                let handedOff = items.filter { $0.name == "file" }
                    .compactMap { $0.value.map { URL(fileURLWithPath: $0) } }
                QueueModel.shared.add(handedOff, presetID: presetID)
            } else {
                files.append(url)
            }
        }
        if !files.isEmpty { QueueModel.shared.add(files) }
        application.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = QueueModel.shared
        guard model.hasActiveWork else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Conversions in progress"
        alert.informativeText = "Quitting cancels the running conversion and drops the waiting files. Finished outputs are kept."
        alert.addButton(withTitle: "Keep Converting")
        alert.addButton(withTitle: "Quit Anyway")
        if alert.runModal() == .alertSecondButtonReturn {
            model.cancelAll()
            // Let the cancelled job unwind (SIGTERM → JobFailure → temp-file cleanup)
            // before the process dies, so no .converting-* temps or palette files are
            // stranded. Bounded: quit proceeds after 5s regardless.
            Task { @MainActor in
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while QueueModel.shared.hasActiveWork && ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
