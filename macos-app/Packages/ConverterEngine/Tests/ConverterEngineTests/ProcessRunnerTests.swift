// Regression tests for the panel-reviewed ProcessRunner cancellation contract and
// stdout capture (no ffmpeg needed — uses /bin and /usr/bin tools).

import XCTest
@testable import ConverterEngine

final class ProcessRunnerTests: XCTestCase {

    /// A cancel that lands BEFORE launch must refuse to start the process (the
    /// panel-found race: cancel between runner publication and process.run).
    func testCancelBeforeRunRefusesToLaunch() throws {
        let runner = ProcessRunner()
        runner.cancel()
        let started = Date()
        let result = try runner.run(tool: URL(fileURLWithPath: "/bin/sleep"),
                                    arguments: ["5"])
        XCTAssertTrue(result.wasCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1,
                          "a refused launch must return immediately, not run sleep 5")
    }

    func testCancelDuringRunTerminates() throws {
        let runner = ProcessRunner()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { runner.cancel() }
        let started = Date()
        let result = try runner.run(tool: URL(fileURLWithPath: "/bin/sleep"),
                                    arguments: ["30"])
        XCTAssertTrue(result.wasCancelled)
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testCaptureStdoutReturnsFullOutput() throws {
        let runner = ProcessRunner()
        let result = try runner.run(tool: URL(fileURLWithPath: "/bin/echo"),
                                    arguments: ["hello"],
                                    captureStdout: true)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(String(data: result.stdoutData ?? Data(), encoding: .utf8), "hello\n")
    }

    func testStderrTailCapturedOnFailure() throws {
        let runner = ProcessRunner()
        let result = try runner.run(tool: URL(fileURLWithPath: "/bin/cat"),
                                    arguments: ["/nonexistent-\(UUID().uuidString)"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.stderrTail.isEmpty)
    }
}
