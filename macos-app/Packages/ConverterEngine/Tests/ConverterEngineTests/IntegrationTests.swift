// End-to-end tests against real ffmpeg/ffprobe/gifsicle (Homebrew during M0b; the
// same tests run against Vendor/ binaries once pinned). Skipped when tools are absent
// so `swift test` stays green on a bare CI box.
//
// Per PRD §6: assertions are MEDIA PROPERTIES (codec, pix_fmt, hvc1 tag, audio
// presence, trimmed duration) — not file-size percentages.

import XCTest
@testable import ConverterEngine

final class IntegrationTests: XCTestCase {

    static var tools: Tools?
    static var fixtures: URL!
    static var silentClip: URL!   // 2s 320x240 synthetic, no audio
    static var aacClip: URL!      // 2s with AAC audio
    static var pcmClip: URL!      // 2s with PCM audio (forces transcode path)

    override class func setUp() {
        super.setUp()
        tools = Tools.locate() // CONVERTER_TOOLS_DIR override → Vendor/ acceptance gate
        guard let tools else { return }
        fixtures = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-fixtures-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)

        func generate(_ name: String, _ extraArgs: [String]) -> URL {
            let url = fixtures.appendingPathComponent(name)
            let process = Process()
            process.executableURL = tools.ffmpeg
            process.arguments = ["-y", "-v", "error",
                                 "-f", "lavfi", "-i", "testsrc=duration=2:size=320x240:rate=15"]
                + extraArgs + [url.path]
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            return url
        }
        silentClip = generate("silent.mp4", ["-pix_fmt", "yuv420p", "-c:v", "libx264"])
        aacClip = generate("aac.mp4", ["-f", "lavfi", "-i", "sine=frequency=440:duration=2",
                                       "-shortest", "-pix_fmt", "yuv420p",
                                       "-c:v", "libx264", "-c:a", "aac"])
        pcmClip = generate("pcm.mov", ["-f", "lavfi", "-i", "sine=frequency=440:duration=2",
                                       "-shortest", "-pix_fmt", "yuv420p",
                                       "-c:v", "libx264", "-c:a", "pcm_s16le"])
    }

    override class func tearDown() {
        if let fixtures { try? FileManager.default.removeItem(at: fixtures) }
        super.tearDown()
    }

    private func requireTools() throws -> Tools {
        try XCTSkipIf(Self.tools == nil, "ffmpeg/ffprobe/gifsicle not installed — skipping integration tests")
        return Self.tools!
    }

    private func probe(_ url: URL, _ tools: Tools) throws -> MediaInfo {
        try MediaProbe.probe(source: url, ffprobe: tools.ffprobe)
    }

    /// Raw ffprobe stream JSON for property assertions beyond MediaInfo.
    private func streamJSON(_ url: URL, _ tools: Tools) throws -> [[String: Any]] {
        let process = Process()
        process.executableURL = tools.ffprobe
        process.arguments = ["-v", "error", "-print_format", "json", "-show_streams", url.path]
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["streams"] as? [[String: Any]] ?? []
    }

    func testProbeDetectsSilenceAndAudio_B10() throws {
        let tools = try requireTools()
        XCTAssertFalse(try probe(Self.silentClip, tools).hasAudio, "B10: silent video must probe as silent")
        let aac = try probe(Self.aacClip, tools)
        XCTAssertTrue(aac.hasAudio)
        XCTAssertEqual(aac.audioCodec, "aac")
    }

    func testH264PresetProducesCompatibleMP4() throws {
        let tools = try requireTools()
        let job = ConversionJob(source: Self.aacClip, preset: .mp4H264, tools: tools)
        let output = try job.run()
        defer { try? FileManager.default.removeItem(at: output) }

        let streams = try streamJSON(output, tools)
        let video = streams.first { $0["codec_type"] as? String == "video" }!
        XCTAssertEqual(video["codec_name"] as? String, "h264")
        XCTAssertEqual(video["pix_fmt"] as? String, "yuv420p", "B2")
        let audio = streams.first { $0["codec_type"] as? String == "audio" }
        XCTAssertEqual(audio?["codec_name"] as? String, "aac")
    }

    /// B11 regression: an 854×480 source (width 2 mod 4, common 480p geometry)
    /// halves to an odd 427 with the script's iw/2 and libx264 refuses to encode;
    /// the even-safe trunc(iw/4)*2 must produce 426×240 instead of failing.
    func testHalfSizeHandlesOddHalfWidth_B11() throws {
        let tools = try requireTools()
        let source = Self.fixtures.appendingPathComponent("wide854.mp4")
        let process = Process()
        process.executableURL = tools.ffmpeg
        process.arguments = ["-y", "-v", "error",
                             "-f", "lavfi", "-i", "testsrc=duration=1:size=854x480:rate=15",
                             "-pix_fmt", "yuv420p", "-c:v", "libx264", source.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let job = ConversionJob(source: source, preset: .mp4H264Half, tools: tools)
        let output = try job.run()
        defer { try? FileManager.default.removeItem(at: output) }

        let video = try streamJSON(output, tools).first { $0["codec_type"] as? String == "video" }!
        XCTAssertEqual(video["width"] as? Int, 426)
        XCTAssertEqual(video["height"] as? Int, 240)
    }

    func testH265PresetTagsHvc1_B9() throws {
        let tools = try requireTools()
        let job = ConversionJob(source: Self.silentClip, preset: .mp4H265Half, tools: tools)
        let output = try job.run()
        defer { try? FileManager.default.removeItem(at: output) }

        let streams = try streamJSON(output, tools)
        let video = streams.first { $0["codec_type"] as? String == "video" }!
        XCTAssertEqual(video["codec_name"] as? String, "hevc")
        XCTAssertEqual(video["codec_tag_string"] as? String, "hvc1", "B9: QuickTime-playable tag")
        XCTAssertEqual(video["width"] as? Int, 160, "half of 320")
        XCTAssertNil(streams.first { $0["codec_type"] as? String == "audio" },
                     "B10: silent source must produce silent output (-an)")
    }

    /// M3 fast tier: hardware HEVC via VideoToolbox must produce the same media
    /// properties as software HEVC (hvc1 tag, silent output for silent source).
    func testHEVCVTPresetTagsHvc1() throws {
        let tools = try requireTools()
        let job = ConversionJob(source: Self.silentClip, preset: .mp4HEVCVT, tools: tools)
        let output = try job.run()
        defer { try? FileManager.default.removeItem(at: output) }

        let streams = try streamJSON(output, tools)
        let video = streams.first { $0["codec_type"] as? String == "video" }!
        XCTAssertEqual(video["codec_name"] as? String, "hevc")
        XCTAssertEqual(video["codec_tag_string"] as? String, "hvc1")
        XCTAssertNil(streams.first { $0["codec_type"] as? String == "audio" })
    }

    func testPCMAudioTranscodesAACStreamCopies_B6() throws {
        let tools = try requireTools()
        // PCM source → transcode
        let pcmInfo = try probe(Self.pcmClip, tools)
        XCTAssertEqual(pcmInfo.audioPlan.mode, .transcodeAAC)
        // AAC source → stream copy
        let aacInfo = try probe(Self.aacClip, tools)
        XCTAssertEqual(aacInfo.audioPlan.mode, .copy)
    }

    func testGifPresetEndToEnd_B1() throws {
        let tools = try requireTools()
        var preset = Preset.gifSmall
        // Also exercise the B1 trim path: 0.5s–1.5s of the 2s clip.
        preset = Preset(id: preset.id, displayName: preset.displayName,
                        options: {
                            var opts = preset.options
                            opts.trim = Trim(start: "0.5", end: "1.5")
                            return opts
                        }(),
                        filenameSuffix: preset.filenameSuffix, fileExtension: preset.fileExtension)
        let job = ConversionJob(source: Self.silentClip, preset: preset, tools: tools)
        let output = try job.run()
        defer { try? FileManager.default.removeItem(at: output) }

        let info = try probe(output, tools)
        // 2s source trimmed to ~1s at 6fps. The shell script HARD-FAILS this exact
        // case on ffmpeg 8 (B1) — success with a sane duration is the parity fix.
        let duration = info.durationSeconds ?? 0
        XCTAssertGreaterThan(duration, 0.6)
        XCTAssertLessThan(duration, 1.5)
        XCTAssertEqual(info.width, 106, "iw/3 of 320, even-rounded")
    }

    func testProgressReportsMonotonicallyToCompletion() throws {
        let tools = try requireTools()
        let job = ConversionJob(source: Self.aacClip, preset: .mp4H264, tools: tools)
        let recorder = ProgressRecorder()
        let output = try job.run { recorder.record($0) }
        defer { try? FileManager.default.removeItem(at: output) }

        let values = recorder.values()
        XCTAssertEqual(values.last, 1.0, "completion must report 1.0")
        let determinate = values.compactMap { $0 }
        XCTAssertEqual(determinate, determinate.sorted(), "progress must be monotonic")
    }

    /// Canonical spec parity: vid2gif_func.sh treats a gifsicle failure as a warning
    /// and keeps the rendered GIF — the job must succeed with the unoptimized file.
    func testGifsicleFailureKeepsRenderedGif() throws {
        let tools = try requireTools()
        let brokenTools = Tools(ffmpeg: tools.ffmpeg, ffprobe: tools.ffprobe,
                                gifsicle: URL(fileURLWithPath: "/usr/bin/false"))
        let job = ConversionJob(source: Self.silentClip, preset: .gifSmall, tools: brokenTools)
        let output = try job.run()
        defer { try? FileManager.default.removeItem(at: output) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let info = try probe(output, tools)
        XCTAssertGreaterThan(info.durationSeconds ?? 0, 1.0, "unoptimized GIF must be intact")
    }

    /// Panel finding: a gifsicle LAUNCH error (missing binary — ProcessRunner throws
    /// a plain Error, not a JobFailure) must get the same keep-the-GIF treatment as
    /// a nonzero exit; it used to bypass the catch and fail the whole job.
    func testGifsicleLaunchFailureKeepsRenderedGif() throws {
        let tools = try requireTools()
        let brokenTools = Tools(ffmpeg: tools.ffmpeg, ffprobe: tools.ffprobe,
                                gifsicle: URL(fileURLWithPath: "/nonexistent/gifsicle"))
        let job = ConversionJob(source: Self.silentClip, preset: .gifSmall, tools: brokenTools)
        let output = try job.run()
        defer { try? FileManager.default.removeItem(at: output) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let info = try probe(output, tools)
        XCTAssertGreaterThan(info.durationSeconds ?? 0, 1.0, "unoptimized GIF must be intact")
    }

    func testFailureCapturesStderrTail_B8() throws {
        let tools = try requireTools()
        let garbage = Self.fixtures.appendingPathComponent("not-a-video.mov")
        try Data("this is not a movie".utf8).write(to: garbage)
        let job = ConversionJob(source: garbage, preset: .mp4H264, tools: tools)
        XCTAssertThrowsError(try job.run()) { error in
            guard let failure = error as? JobFailure else {
                return XCTFail("expected JobFailure, got \(error)")
            }
            XCTAssertFalse(failure.stderrTail.isEmpty, "B8: real error text must be captured")
        }
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double?] = []
    func record(_ value: Double?) {
        lock.lock(); recorded.append(value); lock.unlock()
    }
    func values() -> [Double?] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
}
