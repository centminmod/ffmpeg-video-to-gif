// Main window: preset row → drop zone → queue. Drop implementation is
// .dropDestination(for: URL.self) per the S1 spike verdict.

import SwiftUI
import ConverterEngine
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: QueueModel
    @State private var isDropTargeted = false
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 12) {
            if model.tools == nil { missingToolsBanner }
            presetRow
            dropZone
            queueList
        }
        .padding(12)
        .toolbar {
            ToolbarItem {
                Button("Add Videos…", systemImage: "plus") { showImporter = true }
                    .disabled(model.tools == nil)
            }
            ToolbarItem {
                Button("Clear Finished", systemImage: "trash") { model.clearFinished() }
                    .disabled(!model.hasFinishedItems)
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: QueueModel.importContentTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.add(urls) }
        }
    }

    // MARK: pieces

    private var missingToolsBanner: some View {
        Label("ffmpeg/ffprobe/gifsicle not found — launch the built app bundle (build-app.sh) or `brew install ffmpeg gifsicle`",
              systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(Preset.all) { preset in
                let isSelected = model.selectedPresetID == preset.id
                Button {
                    model.selectedPresetID = preset.id
                } label: {
                    Text(Self.chipName(for: preset))
                        .font(.callout)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(isSelected ? AnyShapeStyle(Color.accentColor)
                                               : AnyShapeStyle(.quaternary),
                                    in: Capsule())
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white)
                                                    : AnyShapeStyle(.primary))
                }
                .buttonStyle(.plain)
                .help(preset.displayName)
            }
            Spacer()
        }
    }

    static func chipName(for preset: Preset) -> String {
        switch preset.id {
        case Preset.mp4H264.id: "H.264"
        case Preset.mp4H264Half.id: "H.264 ½"
        case Preset.mp4H265.id: "H.265"
        case Preset.mp4H265Half.id: "H.265 ½"
        case Preset.gifSmall.id: "GIF ⅓"
        case Preset.gifFull.id: "GIF"
        default: preset.displayName
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Drop videos here")
                .foregroundStyle(.secondary)
            Text("converted with “\(model.selectedPreset.displayName)”, saved next to the original")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6]))
                .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .dropDestination(for: URL.self) { urls, _ in
            let skipped = model.add(urls)
            return skipped < urls.count // false only if NOTHING was a queueable video
        } isTargeted: {
            isDropTargeted = $0
        }
    }

    private var queueList: some View {
        List {
            if model.items.isEmpty {
                Text("Queue is empty")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            }
            ForEach(model.items) { item in
                QueueRow(item: item)
            }
        }
        .listStyle(.inset)
        .frame(minHeight: 160)
    }
}

// MARK: - queue row

struct QueueRow: View {
    let item: QueueItem
    @EnvironmentObject private var model: QueueModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.sourceName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.presetName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                trailing
            }
            if case .running(let fraction) = item.state {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
            if case .failed(let failure) = item.state, !failure.wasCancelled {
                DisclosureGroup {
                    Text(errorDetail(failure))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Error details").font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func errorDetail(_ failure: JobFailure) -> String {
        let tail = failure.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = "\(failure.step) failed" +
            (failure.exitCode.map { " (exit \($0))" } ?? "")
        return tail.isEmpty ? heading : "\(heading)\n\(tail)"
    }

    @ViewBuilder private var statusIcon: some View {
        switch item.state {
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Color.accentColor)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let failure):
            Image(systemName: failure.wasCancelled ? "slash.circle" : "xmark.circle.fill")
                .foregroundStyle(failure.wasCancelled ? Color.secondary : Color.red)
        }
    }

    private var removeButton: some View {
        Button("Remove from list", systemImage: "xmark") { model.removeFinished(id: item.id) }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove from list")
    }

    @ViewBuilder private var trailing: some View {
        switch item.state {
        case .waiting:
            Button("Remove", systemImage: "xmark") { model.cancel(id: item.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        case .running(let fraction):
            if let fraction {
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", systemImage: "xmark") { model.cancel(id: item.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        case .done(let output):
            MediaInfoButton(url: item.job.source, bytes: item.sourceBytes,
                            help: "Original video info")
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            MediaInfoButton(url: output, bytes: item.outputBytes,
                            help: "Converted video info")
            if let source = item.sourceBytes, let converted = item.outputBytes, source > 0 {
                let delta = Double(converted - source) / Double(source)
                Text(delta.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always())))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(delta < 0 ? .green : .orange)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([output])
            }
            .controlSize(.small)
            removeButton
        case .failed(let failure):
            Text(failure.wasCancelled ? "Cancelled" : "Failed")
                .font(.caption)
                .foregroundStyle(failure.wasCancelled ? Color.secondary : Color.red)
            removeButton
        }
    }
}

// MARK: - size badge + metadata popover

/// "12.3 MB ⓘ" — the file's size with a click-for-metadata popover (probed lazily
/// with ffprobe on first open, then cached for the row's lifetime).
private struct MediaInfoButton: View {
    let url: URL
    let bytes: Int64?
    let help: String
    @EnvironmentObject private var model: QueueModel
    @State private var showPopover = false
    @State private var rows: [(label: String, value: String)]?
    @State private var errorText: String?

    var body: some View {
        Button {
            showPopover = true
        } label: {
            HStack(spacing: 3) {
                Text(bytes.map { $0.formatted(.byteCount(style: .file)) } ?? "—")
                    .font(.caption.monospacedDigit())
                Image(systemName: "info.circle")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    @ViewBuilder private var popoverContent: some View {
        Group {
            if let rows {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(rows, id: \.label) { row in
                        GridRow {
                            Text(row.label).foregroundStyle(.secondary)
                            Text(row.value).textSelection(.enabled)
                        }
                    }
                }
            } else if let errorText {
                Text(errorText).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .font(.caption)
        .padding(12)
        .frame(minWidth: 200, alignment: .leading)
        .task { await load() }
    }

    private func load() async {
        guard rows == nil, errorText == nil else { return }
        guard let ffprobe = model.tools?.ffprobe else {
            errorText = "ffprobe unavailable"
            return
        }
        let url = url
        let result: Result<MediaDetails, Error> = await Task.detached(priority: .userInitiated) {
            Result { try MediaDetails.probe(url: url, ffprobe: ffprobe) }
        }.value
        switch result {
        case .success(let details): rows = details.rows
        case .failure(let error): errorText = error.localizedDescription
        }
    }
}
