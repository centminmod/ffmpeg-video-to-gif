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
    /// Display string ("0:05–0:20") captured at creation — the trim fields are
    /// per-session and may change while this job is still queued.
    let trimLabel: String?
    var state: State = .waiting
    /// Captured when the job finishes (the source could be moved/deleted afterwards).
    var sourceBytes: Int64?
    var outputBytes: Int64?

    var sourceName: String { job.source.lastPathComponent }
}

@MainActor
final class QueueModel: ObservableObject {
    static let shared = QueueModel()

    @Published var items: [QueueItem] = []
    @Published var selectedPresetID: String = Preset.mp4H264.id
    // Not persisted — a trim is per-session intent, not a setting.
    @Published var trimStart: String = ""
    @Published var trimEnd: String = ""

    let tools = Tools.locate()
    private var isWorking = false

    /// Resolved through PresetStore so overrides and custom presets apply
    /// (falls back to mp4H264 if the selected custom was deleted).
    var selectedPreset: Preset {
        PresetStore.shared.preset(withID: selectedPresetID) ?? .mp4H264
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

    // MARK: trim

    /// Loose check for ffmpeg time syntax: SS(.ms), MM:SS(.ms), or HH:MM:SS(.ms).
    /// Deliberately permissive — ffmpeg itself is the final validator; this only
    /// keeps obviously malformed input out of jobs (and drives the red UI flag).
    static func isValidTime(_ text: String) -> Bool {
        text.range(of: #"^\d+(:[0-5]?\d){0,2}(\.\d+)?$"#, options: .regularExpression) != nil
    }

    /// The Trim built from the current fields, or nil when neither holds a valid
    /// time. Invalid non-empty input is ignored here (that field contributes
    /// nothing to jobs) and flagged red in the trim bar; a backwards range is
    /// ignored as a whole (see trimRangeInvalid).
    var activeTrim: Trim? {
        guard !trimRangeInvalid else { return nil }
        let start = Self.sanitizedTime(trimStart)
        let end = Self.sanitizedTime(trimEnd)
        guard start != nil || end != nil else { return nil }
        return Trim(start: start, end: end)
    }

    /// True when both fields hold valid times but start >= end — ffmpeg aborts
    /// every such job with "-to value smaller than -ss" (trim is input-side
    /// -ss/-to), so the combination is dropped from jobs and flagged red.
    var trimRangeInvalid: Bool {
        guard let start = Self.sanitizedTime(trimStart).map(Self.seconds),
              let end = Self.sanitizedTime(trimEnd).map(Self.seconds)
        else { return false }
        return start >= end
    }

    /// Display form of activeTrim, e.g. "0:05–0:20" ("start–0:20" when one-sided).
    var activeTrimLabel: String? {
        guard let trim = activeTrim else { return nil }
        return "\(trim.start ?? "start")–\(trim.end ?? "end")"
    }

    private static func sanitizedTime(_ field: String) -> String? {
        let text = field.trimmingCharacters(in: .whitespaces)
        return (!text.isEmpty && isValidTime(text)) ? text : nil
    }

    /// Seconds for a string isValidTime accepted ("1:05" → 65). The regex caps
    /// components at three and 0–59 for minutes/seconds, so left-fold by 60.
    private static func seconds(_ text: String) -> Double {
        text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    // MARK: intake

    /// Queues the video files among `urls` and returns how many entries were skipped
    /// (non-videos, and folders containing no videos). Folders are searched
    /// recursively (M3). `presetID` (from a Quick Action handoff) overrides the
    /// preset selected in the window; unknown/nil falls back to the current selection.
    @discardableResult
    func add(_ urls: [URL], presetID: String? = nil) -> Int {
        guard let tools else { return urls.count }
        var preset = presetID.flatMap { PresetStore.shared.preset(withID: $0) } ?? selectedPreset
        let trimLabel: String?
        // Window-originated intake only: a Finder Quick Action (presetID != nil)
        // must not silently inherit a trim left set in a possibly background window.
        if presetID == nil, let trim = activeTrim {
            // Per-job copy with the trim; same id/suffix — repeated outputs are
            // covered by ConversionJob's collision-safe "-2" naming.
            var options = preset.options
            options.trim = trim
            preset = Preset(id: preset.id, displayName: preset.displayName,
                            options: options, filenameSuffix: preset.filenameSuffix,
                            fileExtension: preset.fileExtension)
            trimLabel = activeTrimLabel
        } else {
            trimLabel = nil
        }
        var skipped = 0
        for url in urls {
            let videos: [URL]
            if Self.isDirectory(url) {
                videos = Self.videosInFolder(url)
            } else {
                videos = Self.isVideoFile(url) ? [url] : []
            }
            guard !videos.isEmpty else { skipped += 1; continue }
            for video in videos {
                items.append(QueueItem(job: ConversionJob(source: video, preset: preset, tools: tools),
                                       presetName: preset.displayName,
                                       trimLabel: trimLabel))
            }
        }
        pump()
        return skipped
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// All video files under `folder`, recursively, in stable path order. Hidden
    /// files and package contents (e.g. .app, Final Cut libraries) are skipped.
    private static func videosInFolder(_ folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var videos: [URL] = []
        for case let child as URL in enumerator where isVideoFile(child) {
            videos.append(child)
        }
        return videos.sorted { $0.path < $1.path }
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
            switch outcome {
            case .done(let output):
                items[i].sourceBytes = Self.fileSize(items[i].job.source)
                items[i].outputBytes = Self.fileSize(output)
                Notifier.postIfBackground(title: "Conversion finished",
                                          body: output.lastPathComponent)
            case .failed(let failure) where !failure.wasCancelled:
                Notifier.postIfBackground(title: "Conversion failed",
                                          body: items[i].sourceName)
            default:
                break
            }
        }
        isWorking = false
        pump()
    }

    private static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
            .flatMap { $0 }
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

    /// Removes a single finished (done/failed) row; running/waiting rows go
    /// through cancel(id:) instead.
    func removeFinished(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        switch items[i].state {
        case .done, .failed: items.remove(at: i)
        case .waiting, .running: break
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
