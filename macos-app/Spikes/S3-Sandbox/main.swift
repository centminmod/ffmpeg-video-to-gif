// M0a S3 — App Sandbox spike (Phase 2 feasibility; Phase 1 ships sandbox-off).
// Built + ad-hoc signed WITH the sandbox entitlement by run.sh, then answers:
//   T1  does a spawned child process inherit security-scoped read access to a
//       user-picked file? (PRD §3: "spike early")
//   T2  can we create a NEW file next to the picked source with only
//       files.user-selected.read-write? (PRD §7 expects NO → fallback output dir)
//   T3  (optional) does a bundled helper in Contents/Helpers run at all under
//       the inherit entitlement? Pass a STATIC ffprobe to run.sh — a Homebrew
//       ffprobe can't load its /opt/homebrew dylibs inside the sandbox.
// Results land in the window and on stdout.

import AppKit
import UniformTypeIdentifiers

final class SpikeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let textView = NSTextView()

    func log(_ msg: String) {
        print(msg)
        textView.string += msg + "\n"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 680, height: 420))
        textView.frame = scroll.bounds
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        scroll.documentView = textView
        scroll.hasVerticalScroller = true

        window = NSWindow(contentRect: scroll.frame,
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Sandbox Spike (M0a S3)"
        window.contentView = scroll
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        log("sandboxed: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil ? "YES" : "NO (entitlement missing — rebuild via run.sh)")")

        let panel = NSOpenPanel()
        panel.message = "Pick any video file"
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { self.log("no file picked"); return }
            self.runTests(on: url)
        }
    }

    func runTests(on url: URL) {
        log("picked: \(url.path)")
        log("startAccessingSecurityScopedResource: \(url.startAccessingSecurityScopedResource())")

        // T1 — child inherits scoped read access?
        let cat = Process()
        cat.executableURL = URL(fileURLWithPath: "/bin/cat")
        cat.arguments = [url.path]
        let out = Pipe()
        cat.standardOutput = out
        cat.standardError = Pipe()
        do {
            try cat.run()
            let bytes = out.fileHandleForReading.readData(ofLength: 16).count
            cat.terminate()
            cat.waitUntilExit()
            log(bytes > 0
                ? "T1 PASS — child /bin/cat read \(bytes) bytes (scoped access inherited)"
                : "T1 FAIL — child spawned but read 0 bytes (scoped access NOT inherited)")
        } catch {
            log("T1 FAIL — child spawn refused: \(error.localizedDescription)")
        }

        // T2 — write a NEW sibling next to the source?
        let sibling = url.deletingPathExtension().appendingPathExtension("sandboxspike.txt")
        do {
            try "sandbox spike marker — safe to delete".write(to: sibling, atomically: true, encoding: .utf8)
            log("T2 PASS — created \(sibling.lastPathComponent) next to source (delete it manually)")
        } catch {
            log("T2 FAIL (PRD expected) — \(error.localizedDescription) → v1 needs a fallback output folder when sandboxed")
        }

        // T3 — bundled helper under com.apple.security.inherit
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ffprobe")
        guard FileManager.default.fileExists(atPath: helper.path) else {
            log("T3 SKIPPED — no bundled ffprobe (rerun: ./run.sh /path/to/static/ffprobe)")
            return
        }
        let probe = Process()
        probe.executableURL = helper
        probe.arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", url.path]
        let probeOut = Pipe()
        probe.standardOutput = probeOut
        probe.standardError = Pipe()
        do {
            try probe.run()
            probe.waitUntilExit()
            let duration = String(data: probeOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            log(probe.terminationStatus == 0 && !duration.isEmpty
                ? "T3 PASS — bundled ffprobe ran, duration=\(duration)s"
                : "T3 FAIL — ffprobe exit \(probe.terminationStatus) (dyld/entitlement issue? must be a STATIC binary)")
        } catch {
            log("T3 FAIL — helper spawn refused: \(error.localizedDescription)")
        }
    }
}

let app = NSApplication.shared
let delegate = SpikeDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
