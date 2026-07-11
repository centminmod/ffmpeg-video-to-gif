// M2 Finder Quick Action handler ("Convert with VidConvert"), per the S2 spike verdict.
// Non-UI Action Extension: collects the selected files' in-place URLs and hands them to
// the containing VidConvert.app, which queues them like a drop.
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

    func beginRequest(with context: NSExtensionContext) {
        let providers = context.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

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

        group.notify(queue: .main) {
            let finish = { context.completeRequest(returningItems: context.inputItems) }
            let sorted = urls.sorted { $0.path < $1.path }
            guard !sorted.isEmpty else {
                NSLog("VidConvertAction: no in-place file URLs in selection")
                return finish()
            }
            // .appex is at VidConvert.app/Contents/PlugIns/VidConvertAction.appex
            let appURL = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(sorted, withApplicationAt: appURL,
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
