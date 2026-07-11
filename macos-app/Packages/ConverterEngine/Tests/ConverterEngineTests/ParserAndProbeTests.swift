import XCTest
@testable import ConverterEngine

final class ProgressParserTests: XCTestCase {

    func testParsesBlocksAndMicrosecondFields() {
        var parser = ProgressParser()
        let chunk = """
        frame=120
        out_time_us=4000000
        speed=2.5x
        progress=continue
        frame=240
        out_time_ms=8000000
        speed=2.4x
        progress=end

        """
        let snapshots = parser.consume(chunk)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].outTimeSeconds, 4.0)
        XCTAssertEqual(snapshots[0].frame, 120)
        XCTAssertEqual(snapshots[0].speed, 2.5)
        XCTAssertFalse(snapshots[0].isEnd)
        // out_time_ms is ALSO microseconds (ffmpeg naming bug) — must not read as ms.
        XCTAssertEqual(snapshots[1].outTimeSeconds, 8.0)
        XCTAssertTrue(snapshots[1].isEnd)
    }

    func testHandlesChunksSplitMidLine() {
        var parser = ProgressParser()
        XCTAssertTrue(parser.consume("out_time_us=100").isEmpty)
        let snapshots = parser.consume("0000\nprogress=continue\n")
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].outTimeSeconds, 1.0)
    }

    func testNAOutTimeYieldsNilFraction() {
        var parser = ProgressParser()
        let snapshots = parser.consume("out_time_us=N/A\nprogress=continue\n")
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertNil(snapshots[0].outTimeSeconds)
        XCTAssertNil(ProgressParser.fraction(of: snapshots[0], effectiveDuration: 10))
    }

    func testFractionClampsAndDividesByEffectiveDuration() {
        let snapshot = ProgressSnapshot(outTimeSeconds: 5, frame: nil, speed: nil, isEnd: false)
        XCTAssertEqual(ProgressParser.fraction(of: snapshot, effectiveDuration: 10), 0.5)
        XCTAssertEqual(ProgressParser.fraction(of: snapshot, effectiveDuration: 2), 1.0, "clamped")
        XCTAssertNil(ProgressParser.fraction(of: snapshot, effectiveDuration: nil),
                     "unknown duration → indeterminate")
    }
}

final class MediaProbeParseTests: XCTestCase {

    func testParsesAudioVideoAndDuration() throws {
        let json = """
        {"streams":[
            {"codec_type":"video","codec_name":"h264","width":1920,"height":1080},
            {"codec_type":"audio","codec_name":"aac"}],
         "format":{"duration":"12.5"}}
        """.data(using: .utf8)!
        let info = try MediaProbe.parse(json: json)
        XCTAssertEqual(info.durationSeconds, 12.5)
        XCTAssertEqual(info.width, 1920)
        XCTAssertTrue(info.hasAudio)
        XCTAssertEqual(info.audioCodec, "aac")
        XCTAssertEqual(info.audioPlan.mode, .copy)
    }

    func testSilentVideoHasNoAudio_B10() throws {
        // B10: the shell script would have said has_audio=true here (exit-status check).
        let json = """
        {"streams":[{"codec_type":"video","codec_name":"h264","width":640,"height":480}],
         "format":{"duration":"3.0"}}
        """.data(using: .utf8)!
        let info = try MediaProbe.parse(json: json)
        XCTAssertFalse(info.hasAudio)
        XCTAssertEqual(info.audioPlan.mode, .none)
    }

    func testNADurationParsesAsNil() throws {
        let json = """
        {"streams":[{"codec_type":"video"}],"format":{"duration":"N/A"}}
        """.data(using: .utf8)!
        let info = try MediaProbe.parse(json: json)
        XCTAssertNil(info.durationSeconds)
        XCTAssertNil(info.effectiveDuration(trim: Trim()))
    }

    func testEffectiveDurationRespectsTrim() throws {
        let info = MediaInfo(durationSeconds: 60, width: nil, height: nil,
                             hasAudio: false, audioCodec: nil)
        XCTAssertEqual(info.effectiveDuration(trim: Trim(start: "10", end: "25")), 15)
        XCTAssertEqual(info.effectiveDuration(trim: Trim(start: "0:30")), 30)
        XCTAssertEqual(info.effectiveDuration(trim: Trim(end: "100")), 60, "end past EOF clamps")
        XCTAssertNil(info.effectiveDuration(trim: Trim(start: "90")), "start past EOF → nil")
    }

    func testTimeExpressionParsing() {
        XCTAssertEqual(MediaProbe.seconds(fromTimeExpression: "90"), 90)
        XCTAssertEqual(MediaProbe.seconds(fromTimeExpression: "1:30"), 90)
        XCTAssertEqual(MediaProbe.seconds(fromTimeExpression: "01:02:03.5"), 3723.5)
        XCTAssertNil(MediaProbe.seconds(fromTimeExpression: "abc"))
        XCTAssertNil(MediaProbe.seconds(fromTimeExpression: "1:2:3:4"))
    }
}

final class NamingTests: XCTestCase {

    func testCollisionSafeNaming() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("naming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("clip.mov")
        let first = ConversionJob.destination(for: source, preset: .mp4H264)
        XCTAssertEqual(first.lastPathComponent, "clip-h264_crf33.mp4")

        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = ConversionJob.destination(for: source, preset: .mp4H264)
        XCTAssertEqual(second.lastPathComponent, "clip-h264_crf33-2.mp4", "B8: never overwrite")
    }
}
