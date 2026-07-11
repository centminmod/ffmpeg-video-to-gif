// S2 Vehicle A — non-UI Action Extension handler.
// Paste over the Xcode "Action Extension (No User Interface)" template's handler.
// Spike scope: prove the extension fires from Finder ▸ Quick Actions and receives
// usable file URLs. The real M2 handler additionally writes security-scoped
// bookmarks into the app-group container and activates the main app (PRD §4).
//
// SPIKE FINDINGS BAKED IN (macOS 15.7, verified via unified log):
// 1. Finder registers attachments under the file's CONTENT type (public.mpeg-4 …),
//    NOT public.file-url — a hasItemConformingToTypeIdentifier(.fileURL) filter
//    matches nothing ("received 0 URL(s)"). Ask for the item's own registered type
//    and load a file representation instead.
// 2. Editor role + empty returningItems makes Finder strand the originals in an
//    NSItemReplacementDirectory staging dir (files "vanish"). Info.plist must say
//    NSExtensionServiceRoleTypeViewer and the handler must return inputItems.
// 3. A 3-file Finder multi-select arrives as ONE invocation.

import Foundation
import UniformTypeIdentifiers

final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let items = context.inputItems.compactMap { $0 as? NSExtensionItem }
        let providers = items.flatMap { $0.attachments ?? [] }
        NSLog("QuickActionSpike invoked: %d inputItem(s), %d attachment(s)", items.count, providers.count)

        var received: [String] = []
        let group = DispatchGroup()

        for provider in providers {
            let types = provider.registeredTypeIdentifiers
            NSLog("QuickActionSpike provider types: %@", types.joined(separator: ", "))
            guard let type = types.first else { continue }
            group.enter()
            // In-place is what a converter needs: the original file's URL, not a copy.
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, inPlace, error in
                defer { group.leave() }
                if let url {
                    received.append("\(url.path) [inPlace=\(inPlace)]")
                } else {
                    received.append("LOAD FAILED: \(error?.localizedDescription ?? "?")")
                }
            }
        }

        group.notify(queue: .main) {
            NSLog("QuickActionSpike received %d URL(s): %@",
                  received.count, received.joined(separator: " | "))
            // Viewer role: originals are untouched; returning inputItems unchanged.
            context.completeRequest(returningItems: context.inputItems)
        }
    }
}
