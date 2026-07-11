// M0a S1 — drop-target spike.
// Two drop zones side by side receive the SAME drags so behaviors can be compared:
//   Zone A: .dropDestination(for: URL.self)   — the SwiftUI-native path (PRD Plan A)
//   Zone B: .onDrop(of: [.fileURL]) + NSItemProvider — the fallback if A misbehaves
// Plus .fileImporter for the picker path.
//
// Run: swift run   (from this directory; CLT toolchain is enough)
//
// Test matrix (drag each onto BOTH zones, compare the log):
//   1. single video file from Finder
//   2. multi-file selection from Finder
//   3. a folder (recursion count should match its video files)
//   4. a promised file: drag a photo/video out of Photos.app
//   5. an image dragged from a browser (remote content — expect A to miss or
//      deliver a temp file; log tells which)
// PASS for Zone A = 1–3 deliver correct paths that exist at drop time.

import SwiftUI
import UniformTypeIdentifiers

@main
struct DropTargetSpikeApp: App {
    var body: some Scene {
        WindowGroup("DropTarget Spike (M0a S1)") {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
                .onAppear {
                    // swift-run binaries have no bundle; force a real UI presence
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let text: String
}

@Observable
final class SpikeLog {
    var entries: [LogEntry] = []

    func add(_ zone: String, _ msg: String) {
        entries.append(LogEntry(text: "[\(zone)] \(msg)"))
        print("[\(zone)] \(msg)")
    }

    func inspect(_ zone: String, _ url: URL) {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        // Outside a sandbox this returns false — logged so the same binary can be
        // re-run sandboxed later (S3 territory) and diffed.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var line = url.path
        line += exists ? (isDir.boolValue ? "  (dir)" : "  (file)") : "  (MISSING at drop time — promised file?)"
        line += scoped ? "  [scoped: granted]" : "  [scoped: n/a]"
        add(zone, line)

        if isDir.boolValue {
            add(zone, "  ↳ recursed: \(Self.videoFiles(under: url).count) video file(s)")
        }
    }

    static func videoFiles(under dir: URL) -> [URL] {
        let exts: Set<String> = ["mov", "avi", "mkv", "webm", "mp4", "m4v", "wmv", "flv", "ts", "mpg", "mpeg", "3gp"]
        let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey])
        var found: [URL] = []
        while let f = enumerator?.nextObject() as? URL {
            if exts.contains(f.pathExtension.lowercased()) { found.append(f) }
        }
        return found
    }
}

struct ContentView: View {
    @State private var log = SpikeLog()
    @State private var aTargeted = false
    @State private var bTargeted = false
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                zone("A · dropDestination(URL)", targeted: aTargeted)
                    .dropDestination(for: URL.self) { urls, _ in
                        log.add("A", "drop delivered \(urls.count) URL(s)")
                        urls.forEach { log.inspect("A", $0) }
                        return true
                    } isTargeted: { aTargeted = $0 }

                zone("B · onDrop(.fileURL)", targeted: bTargeted)
                    .onDrop(of: [.fileURL], isTargeted: $bTargeted) { providers in
                        log.add("B", "drop delivered \(providers.count) provider(s)")
                        for provider in providers {
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                                DispatchQueue.main.async {
                                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                        log.inspect("B", url)
                                    } else if let url = item as? URL {
                                        log.inspect("B", url)
                                    } else {
                                        log.add("B", "provider load failed: \(error?.localizedDescription ?? "no fileURL representation")")
                                    }
                                }
                            }
                        }
                        return true
                    }
            }
            .frame(height: 160)

            Button("Pick files… (.fileImporter)") { showImporter = true }
                .fileImporter(isPresented: $showImporter,
                              allowedContentTypes: [.movie, .video],
                              allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): urls.forEach { log.inspect("picker", $0) }
                    case .failure(let error): log.add("picker", "failed: \(error.localizedDescription)")
                    }
                }

            List(log.entries) { entry in
                Text(entry.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding()
    }

    private func zone(_ title: String, targeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(targeted ? Color.accentColor : .secondary,
                          style: StrokeStyle(lineWidth: 2, dash: [6]))
            .background(targeted ? Color.accentColor.opacity(0.15) : .clear)
            .overlay(Text(title).font(.headline))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
