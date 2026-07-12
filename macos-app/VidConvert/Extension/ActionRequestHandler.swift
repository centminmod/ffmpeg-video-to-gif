// M2 Finder Quick Action handler, per the S2 spike verdict. ONE binary, FIVE appexes:
// build-app.sh stamps each copy's Info.plist with a VidConvertPresetID, so the Finder
// menu offers one entry per preset (mirroring the old Automator workflows). The handler
// collects the selected files' in-place URLs and hands them to the containing
// VidConvert.app as a vidconvert:// URL that carries the preset choice.
//
// S2 findings this code depends on (macos-app/Spikes/S2-QuickAction/README.md):
// 1. Finder registers attachments under the file's CONTENT type, not public.file-url —
//    ask each provider for its own registeredTypeIdentifiers.
// 2. loadInPlaceFileRepresentation delivers the ORIGINAL path (inPlace=true) even inside
//    the sandboxed extension process — a converter needs the real file, not a copy.
// 3. Viewer role + returning context.inputItems unchanged; Editor role strands originals
//    in NSItemReplacementDirectory staging dirs.
//
// Handoff is a plain LaunchServices open (app is unsandboxed in Phase 1); the PRD's
// app-group bookmark handoff is only needed once the app itself is sandboxed (Phase 2).
// Built WITHOUT -application-extension so NSWorkspace is callable; launching another app
// through LaunchServices is permitted under the extension's sandbox profile.

import AppKit
import UniformTypeIdentifiers

final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {

    /// completeRequest must run exactly once — the normal path and the watchdog
    /// below race for it (panel finding: without a bound, a stalled provider or a
    /// lost NSWorkspace.open callback left the request pending until macOS killed
    /// the extension with no Finder feedback).
    private let finishLock = NSLock()
    private var finished = false

    /// True exactly once; every completion path goes through this gate.
    private func claimFinish() -> Bool {
        finishLock.lock(); defer { finishLock.unlock() }
        if finished { return false }
        finished = true
        return true
    }

    private var isFinished: Bool {
        finishLock.lock(); defer { finishLock.unlock() }
        return finished
    }

    func beginRequest(with context: NSExtensionContext) {
        let providers = context.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        // Watchdog: extensions get ~30s total; give providers + the app handoff
        // 15s, then return the request as-is rather than hang.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.claimFinish() else { return }
            NSLog("VidConvertAction: timed out waiting for file providers / app handoff")
            context.completeRequest(returningItems: context.inputItems)
        }

        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            guard let type = provider.registeredTypeIdentifiers.first else { continue }
            group.enter()
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, inPlace, _ in
                defer { group.leave() }
                // A non-in-place URL is a temp copy that vanishes after this request
                // completes — useless to queue; the app-side filter drops non-videos.
                if let url, inPlace {
                    lock.lock(); urls.append(url); lock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, !self.isFinished else { return } // watchdog already returned it
            let finish = { [weak self] in
                guard let self, self.claimFinish() else { return }
                context.completeRequest(returningItems: context.inputItems)
            }
            let sorted = urls.sorted { $0.path < $1.path }
            guard !sorted.isEmpty else {
                NSLog("VidConvertAction: no in-place file URLs in selection")
                return finish()
            }
            // .appex is at VidConvert.app/Contents/PlugIns/<this>.appex
            let appURL = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            // Preset rides along in a vidconvert:// URL — plain file-URL opens have no
            // side channel for it. Paths are percent-encoded by URLComponents.
            var components = URLComponents()
            components.scheme = "vidconvert"
            components.host = "convert"
            var query = sorted.map { URLQueryItem(name: "file", value: $0.path) }
            if let presetID = Bundle.main.object(forInfoDictionaryKey: "VidConvertPresetID") as? String {
                query.insert(URLQueryItem(name: "preset", value: presetID), at: 0)
            }
            components.queryItems = query
            guard let handoff = components.url else {
                NSLog("VidConvertAction: could not build handoff URL")
                return finish()
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([handoff], withApplicationAt: appURL,
                                    configuration: configuration) { _, error in
                if let error {
                    NSLog("VidConvertAction: handoff to %@ failed: %@",
                          appURL.path, error.localizedDescription)
                }
                // Complete only after the open round-trips — completing earlier can
                // kill this process before LaunchServices delivers the URLs.
                DispatchQueue.main.async(execute: finish)
            }
        }
    }
}
