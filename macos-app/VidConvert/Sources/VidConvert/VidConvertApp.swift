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
    /// Files handed over by the Finder Quick Action (M2) — or any other
    /// LaunchServices open — queue exactly like a drop, with the preset
    /// currently selected in the window.
    func application(_ application: NSApplication, open urls: [URL]) {
        QueueModel.shared.add(urls)
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
