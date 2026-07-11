// Queue state + serial job execution (PRD §5.3: one conversion at a time — ffmpeg
// already saturates the cores). ConversionJob.run is blocking, so each job runs on a
// detached background task; all state mutation happens back on the main actor.

import SwiftUI
import ConverterEngine
import UniformTypeIdentifiers

struct QueueItem: Identifiable {
    enum State: Sendable {
        case waiting
        case running(Double?)     // nil = indeterminate (source duration unknown)
        case done(URL)
        case failed(JobFailure)
    }

    let id = UUID()
    let job: ConversionJob
    let presetName: String
    var state: State = .waiting

    var sourceName: String { job.source.lastPathComponent }
}

@MainActor
final class QueueModel: ObservableObject {
    static let shared = QueueModel()

    @Published var items: [QueueItem] = []
    @Published var selectedPresetID: String = Preset.mp4H264.id

    let tools = Tools.locate()
    private var isWorking = false

    var selectedPreset: Preset {
        Preset.all.first { $0.id == selectedPresetID } ?? .mp4H264
    }

    var hasActiveWork: Bool {
        items.contains { item in
            switch item.state {
            case .waiting, .running: true
            case .done, .failed: false
            }
        }
    }

    var hasFinishedItems: Bool {
        items.contains { item in
            switch item.state {
            case .done, .failed: true
            case .waiting, .running: false
            }
        }
    }

    // MARK: intake

    /// Queues the video files among `urls` (each with the preset selected NOW) and
    /// returns how many were skipped as non-videos.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        guard let tools else { return urls.count }
        let preset = selectedPreset
        var skipped = 0
        for url in urls {
            guard Self.isVideoFile(url) else { skipped += 1; continue }
            items.append(QueueItem(job: ConversionJob(source: url, preset: preset, tools: tools),
                                   presetName: preset.displayName))
        }
        pump()
        return skipped
    }

    /// What the Open panel offers — kept in sync with isVideoFile's fallback list so
    /// picking and dropping accept the same files.
    static let importContentTypes: [UTType] = [.movie, .video]
        + ["mkv", "webm", "flv", "wmv", "ts", "m2ts"].compactMap { UTType(filenameExtension: $0) }

    static func isVideoFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        let ext = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .movie) || type.conforms(to: .video) { return true }
        // Containers macOS often has no UTType claim for without a third-party app.
        return ["mkv", "webm", "flv", "wmv", "ts", "m2ts"].contains(ext)
    }

    // MARK: serial worker

    private func pump() {
        guard !isWorking else { return }
        guard let index = items.firstIndex(where: { item in
            if case .waiting = item.state { return true } else { return false }
        }) else { return }

        isWorking = true
        let id = items[index].id
        let job = items[index].job
        items[index].state = .running(0)

        let relay = ProgressRelay { fraction in
            QueueModel.shared.setProgress(id: id, fraction: fraction)
        }
        Task.detached(priority: .userInitiated) {
            let outcome: QueueItem.State
            do {
                let output = try job.run { fraction in
                    relay.post(fraction)
                }
                outcome = .done(output)
            } catch let failure as JobFailure {
                outcome = .failed(failure)
            } catch {
                outcome = .failed(JobFailure(step: "unexpected", exitCode: nil,
                                             stderrTail: error.localizedDescription,
                                             wasCancelled: false))
            }
            await MainActor.run {
                QueueModel.shared.complete(id: id, outcome: outcome)
            }
        }
    }

    private func setProgress(id: UUID, fraction: Double?) {
        guard let i = items.firstIndex(where: { $0.id == id }),
              case .running(let old) = items[i].state, old != fraction else { return }
        items[i].state = .running(fraction)
    }

    private func complete(id: UUID, outcome: QueueItem.State) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].state = outcome
        }
        isWorking = false
        pump()
    }

    // MARK: user actions

    /// Waiting items leave the queue; the running item is cancelled (it then completes
    /// through the normal path with wasCancelled = true).
    func cancel(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        switch items[i].state {
        case .waiting: items.remove(at: i)
        case .running: items[i].job.cancel()
        case .done, .failed: break
        }
    }

    func cancelAll() {
        items.removeAll { item in
            if case .waiting = item.state { return true } else { return false }
        }
        for item in items {
            if case .running = item.state { item.job.cancel() }
        }
    }

    func clearFinished() {
        items.removeAll { item in
            switch item.state {
            case .done, .failed: true
            case .waiting, .running: false
            }
        }
    }
}

/// Coalesces high-frequency progress callbacks into at most one pending main-actor
/// delivery of the LATEST value. Spawning an unstructured Task per callback would
/// allocate thousands of tasks per encode and — since unstructured Tasks are not
/// FIFO — could deliver progress out of order, making the bar jump backwards.
final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Double??      // .some(latest fraction) when a delivery is due
    private var scheduled = false
    private let deliver: @MainActor (Double?) -> Void

    init(deliver: @escaping @MainActor (Double?) -> Void) {
        self.deliver = deliver
    }

    func post(_ fraction: Double?) {
        lock.lock()
        pending = .some(fraction)
        let alreadyScheduled = scheduled
        scheduled = true
        lock.unlock()
        guard !alreadyScheduled else { return }
        Task { @MainActor in
            self.lock.lock()
            let value = self.pending
            self.pending = nil
            self.scheduled = false
            self.lock.unlock()
            if case .some(let fraction) = value {
                self.deliver(fraction)
            }
        }
    }
}
