// Spawns one tool invocation, draining stdout (progress) and stderr (diagnostics)
// concurrently — PRD §5 requires concurrent draining to avoid pipe-buffer deadlock —
// with SIGTERM-then-SIGKILL cancellation.

import Foundation

public struct ProcessResult: Sendable {
    public var exitCode: Int32
    public var stderrTail: String   // captured for the failure UX (PRD §5.5)
    public var wasCancelled: Bool
}

public final class ProcessRunner: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    /// Runs to completion (blocking — callers wrap in their own concurrency).
    /// `onProgressChunk` receives raw stdout text on a background queue.
    public func run(tool: URL,
                    arguments: [String],
                    onProgressChunk: (@Sendable (String) -> Void)? = nil) throws -> ProcessResult {
        process.executableURL = tool
        process.arguments = arguments

        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        // Concurrent drains: readabilityHandler runs off-thread, so neither pipe can
        // fill and stall ffmpeg while we wait.
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                onProgressChunk?(text)
            }
        }
        let stderrBuffer = LockedBuffer()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBuffer.append(data)
        }

        try process.run()
        process.waitUntilExit()

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        // Collect any residue left after the handlers detach.
        stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())

        lock.lock()
        let wasCancelled = cancelled
        lock.unlock()

        return ProcessResult(exitCode: process.terminationStatus,
                             stderrTail: stderrBuffer.tail(maxLines: 30),
                             wasCancelled: wasCancelled)
    }

    /// SIGTERM now; SIGKILL if still alive after `killDelay` (PRD §5.3 cancel spec).
    public func cancel(killDelay: TimeInterval = 5) {
        lock.lock()
        cancelled = true
        lock.unlock()
        guard process.isRunning else { return }
        process.terminate() // SIGTERM
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + killDelay) { [weak process] in
            if let process, process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}

/// Thread-safe byte buffer for the stderr drain.
final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func tail(maxLines: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(maxLines).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
