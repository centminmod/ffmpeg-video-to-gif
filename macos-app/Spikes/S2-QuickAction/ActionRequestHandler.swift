// S2 Vehicle A — non-UI Action Extension handler.
// Paste over the Xcode "Action Extension (No User Interface)" template's handler.
// Spike scope: prove the extension fires from Finder ▸ Quick Actions and receives
// usable file URLs. The real M2 handler additionally writes security-scoped
// bookmarks into the app-group container and activates the main app (PRD §4).

import Foundation
import UniformTypeIdentifiers

final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let providers = context.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }

        var received: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    received.append(url)
                } else if let url = item as? URL {
                    received.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            // Visible in Console.app (search: QuickActionSpike). Record: invocation
            // count for a 3-file multi-select, and whether paths are readable here.
            NSLog("QuickActionSpike received %d URL(s): %@",
                  received.count, received.map(\.path).joined(separator: " | "))
            context.completeRequest(returningItems: [])
        }
    }
}
