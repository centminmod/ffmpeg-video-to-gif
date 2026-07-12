// Spawns one tool invocation, draining stdout (progress) and stderr (diagnostics)
// concurrently — PRD §5 requires concurrent draining to avoid pipe-buffer deadlock —
// with SIGTERM-then-SIGKILL cancellation.
//
// Cancellation contract (panel-reviewed): cancel() and the process launch are
// serialized under one lock, so a cancel can never be lost — either it lands before
// process.run() (the launch is refused, wasCancelled = true) or it lands after and
// SIGTERMs a live process. Drains are EOF-driven: each readabilityHandler detaches
// itself when it sees EOF and signals a group, so no post-exit residue read can race
// an in-flight callback on the same handle.

import Foundation

/// libproc's child-pid enumeration (no Swift overlay exists — the symbol lives in
/// libSystem). Returns the number of BYTES written into `buffer`, proc_listpids
/// semantics.
@_silgen_name("proc_listchildpids")
private func proc_listchildpids(_ ppid: pid_t,
                                _ buffer: UnsafeMutableRawPointer?,
                                _ buffersize: CInt) -> CInt

public struct ProcessResult: Sendable {
    public var exitCode: Int32
    public var stdoutData: Data?    // only when captureStdout was requested
    public var stderrTail: String   // captured for the failure UX (PRD §5.5)
    public var wasCancelled: Bool
}

public final class ProcessRunner: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private var started = false

    public init() {}

    /// Runs to completion (blocking — callers wrap in their own concurrency).
    /// `onProgressChunk` receives raw stdout text on a background queue.
    /// Single-use: create a fresh runner per invocation.
    public func run(tool: URL,
                    arguments: [String],
                    captureStdout: Bool = false,
                    onProgressChunk: (@Sendable (String) -> Void)? = nil) throws -> ProcessResult {
        process.executableURL = tool
        process.arguments = arguments

        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let drainGroup = DispatchGroup()
        let stdoutBuffer = LockedBuffer()
        drainGroup.enter()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { // EOF: detach and signal
                handle.readabilityHandler = nil
                drainGroup.leave()
                return
            }
            if captureStdout { stdoutBuffer.append(data) }
            if let onProgressChunk, let text = String(data: data, encoding: .utf8) {
                onProgressChunk(text)
            }
        }
        let stderrBuffer = LockedBuffer()
        drainGroup.enter()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                drainGroup.leave()
                return
            }
            stderrBuffer.append(data)
        }

        func detachHandlers() {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        // Launch under the lock: a concurrent cancel() either marks `cancelled`
        // before we get here (we refuse to launch) or observes a launched process.
        lock.lock()
        precondition(!started, "ProcessRunner instances are single-use")
        started = true
        if cancelled {
            lock.unlock()
            detachHandlers()
            return ProcessResult(exitCode: -1, stdoutData: nil, stderrTail: "", wasCancelled: true)
        }
        do {
            try process.run()
        } catch {
            lock.unlock()
            detachHandlers()
            throw error
        }
        lock.unlock()

        process.waitUntilExit()
        // All writers are gone; wait for both drains to observe EOF (bounded as a
        // belt-and-braces guard — EOF is guaranteed once the child's FDs close).
        _ = drainGroup.wait(timeout: .now() + 5)

        lock.lock()
        let wasCancelled = cancelled
        lock.unlock()

        return ProcessResult(exitCode: process.terminationStatus,
                             stdoutData: captureStdout ? stdoutBuffer.snapshot() : nil,
                             stderrTail: stderrBuffer.tail(maxLines: 30),
                             wasCancelled: wasCancelled)
    }

    /// SIGTERM now; SIGKILL if still alive after `killDelay` (PRD §5.3 cancel spec).
    /// Before launch, marks the runner so `run()` refuses to start the process.
    /// PRD §5.3 says process TREE: children are enumerated (via libproc) and
    /// signalled alongside the direct child — enumerated BEFORE the parent is
    /// terminated, because once the parent exits its children reparent to launchd
    /// and can no longer be found this way. (Our tools spawn at most one level.)
    public func cancel(killDelay: TimeInterval = 5) {
        lock.lock()
        cancelled = true
        let running = started && process.isRunning
        lock.unlock()
        guard running else { return } // not launched yet: run() sees `cancelled` and refuses
        let pid = process.processIdentifier
        let children = Self.childPIDs(of: pid)
        process.terminate() // SIGTERM
        for child in children { kill(child, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + killDelay) { [weak process] in
            if let process, process.isRunning {
                // Re-enumerate: the guard proves the parent is STILL our child
                // (no PID reuse), so its current children are still its own.
                for child in Self.childPIDs(of: pid) { kill(child, SIGKILL) }
                kill(pid, SIGKILL)
            }
        }
    }

    private static func childPIDs(of pid: pid_t) -> [pid_t] {
        // Fixed generous buffer: ffmpeg/ffprobe/gifsicle spawn 0–2 helpers at most.
        var pids = [pid_t](repeating: 0, count: 64)
        let bytes = pids.withUnsafeMutableBytes {
            proc_listchildpids(pid, $0.baseAddress, CInt($0.count))
        }
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).filter { $0 > 0 }
    }
}

/// Thread-safe byte buffer for the pipe drains.
final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
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
