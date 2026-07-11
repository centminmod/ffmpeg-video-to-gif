// Golden-parity tests: the committed Automator wrappers + vid2gif_func.sh are the
// canonical spec. Each test pins the FULL argument array the engine emits for a
// shipped preset, so any drift is a conscious, reviewed change. Deviations from the
// shell script are the PRD §1 bug fixes (B1–B10) — asserted explicitly below.

import XCTest
@testable import ConverterEngine

final class CommandBuilderTests: XCTestCase {

    let src = URL(fileURLWithPath: "/tmp/in/clip.mov")
    let dst = URL(fileURLWithPath: "/tmp/in/clip-out.mp4")
    let gifDst = URL(fileURLWithPath: "/tmp/in/clip-third_size.gif")
    let palette = URL(fileURLWithPath: "/tmp/palette.png")

    // MARK: full-array golden tests, one per shipped MP4 preset

    func testH264FullSizePreset() {
        // Wrapper: vid2gif_pro --src f --to-mp4-h264 --crf 33
        let args = FFmpegCommandBuilder.mp4Command(
            source: src, destination: dst, options: Preset.mp4H264.options,
            audio: AudioPlan(mode: .transcodeAAC))
        XCTAssertEqual(args, [
            "-y", "-nostdin", "-v", "error",
            "-i", "/tmp/in/clip.mov",
            "-c:v", "libx264", "-preset", "medium", "-crf", "33",
            "-pix_fmt", "yuv420p",                 // B2 fix (script had none)
            "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "/tmp/in/clip-out.mp4",
        ])
    }

    func testH264HalfSizePreset() {
        // Wrapper: vid2gif_pro --src f --to-mp4-h264 --crf 29 --half-size
        let args = FFmpegCommandBuilder.mp4Command(
            source: src, destination: dst, options: Preset.mp4H264Half.options,
            audio: AudioPlan(mode: .transcodeAAC))
        XCTAssertEqual(args, [
            "-y", "-nostdin", "-v", "error",
            "-i", "/tmp/in/clip.mov",
            "-vf", "scale=iw/2:-2",                // exact script scale filter
            "-c:v", "libx264", "-preset", "medium", "-crf", "29",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "/tmp/in/clip-out.mp4",
        ])
    }

    func testH265FullSizePreset() {
        // Wrapper: vid2gif_pro --src f --to-mp4-h265 --crf 35
        let args = FFmpegCommandBuilder.mp4Command(
            source: src, destination: dst, options: Preset.mp4H265.options,
            audio: AudioPlan(mode: .transcodeAAC))
        XCTAssertEqual(args, [
            "-y", "-nostdin", "-v", "error",
            "-i", "/tmp/in/clip.mov",
            "-c:v", "libx265", "-preset", "medium", "-crf", "35",
            "-pix_fmt", "yuv420p",
            "-tag:v", "hvc1",                      // B9 fix (script muxed hev1)
            "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "/tmp/in/clip-out.mp4",
        ])
    }

    func testH265HalfSizePreset() {
        // Wrapper: vid2gif_pro --src f --to-mp4-h265 --crf 31 --half-size
        let args = FFmpegCommandBuilder.mp4Command(
            source: src, destination: dst, options: Preset.mp4H265Half.options,
            audio: AudioPlan(mode: .transcodeAAC))
        XCTAssertEqual(args, [
            "-y", "-nostdin", "-v", "error",
            "-i", "/tmp/in/clip.mov",
            "-vf", "scale=iw/2:-2",
            "-c:v", "libx265", "-preset", "medium", "-crf", "31",
            "-pix_fmt", "yuv420p",
            "-tag:v", "hvc1",
            "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "/tmp/in/clip-out.mp4",
        ])
    }

    // MARK: GIF preset (two passes + gifsicle)

    func testGifPalettePassMatchesWrapperPreset() {
        // Wrapper: vid2gif_pro --src f --third-size --lossy --dither bayer --fps 6
        let args = FFmpegCommandBuilder.gifPalettePass(
            source: src, palette: palette, options: Preset.gifSmall.options)
        XCTAssertEqual(args, [
            "-y", "-nostdin", "-v", "error",
            "-i", "/tmp/in/clip.mov",
            "-vf", "scale=iw/3:-2,fps=6,palettegen=stats_mode=diff", // script's exact chain
            "-update", "1",
            "-progress", "pipe:1",
            "/tmp/palette.png",
        ])
    }

    func testGifRenderPassMatchesWrapperPreset() {
        let args = FFmpegCommandBuilder.gifRenderPass(
            source: src, palette: palette, destination: gifDst, options: Preset.gifSmall.options)
        XCTAssertEqual(args, [
            "-y", "-nostdin", "-v", "error",       // B8 fix: script pass 2 used -v quiet
            "-i", "/tmp/in/clip.mov", "-i", "/tmp/palette.png",
            "-filter_complex",
            "[0:v]scale=iw/3:-2,fps=6[s]; [s][1:v]paletteuse=dither=bayer:diff_mode=rectangle",
            "-progress", "pipe:1",
            "/tmp/in/clip-third_size.gif",
        ])
    }

    func testGifsicleMatchesWrapperPreset() {
        // Script: gifsicle --lossy -O3 -o target target
        let args = FFmpegCommandBuilder.gifsicleCommand(target: gifDst, options: Preset.gifSmall.options)
        XCTAssertEqual(args, ["--lossy", "-O3", "-o", gifDst.path, gifDst.path])
    }

    // MARK: B1/B4 — trim placement

    func testTrimIsInputSideOnBothGifPasses() {
        var options = Preset.gifSmall.options
        options.trim = Trim(start: "00:00:05", end: "00:00:10")

        let pass1 = FFmpegCommandBuilder.gifPalettePass(source: src, palette: palette, options: options)
        let pass2 = FFmpegCommandBuilder.gifRenderPass(source: src, palette: palette,
                                                       destination: gifDst, options: options)
        // B4: -ss precedes -i (fast input seek), B1: identical on both passes and
        // NEVER between the two -i inputs of pass 2.
        for args in [pass1, pass2] {
            let ss = args.firstIndex(of: "-ss")!
            let firstInput = args.firstIndex(of: "-i")!
            XCTAssertLessThan(ss, firstInput, "trim must be input-side, before the first -i")
        }
        let secondInput = pass2.lastIndex(of: "-i")!
        let ss2 = pass2.firstIndex(of: "-ss")!
        XCTAssertLessThan(ss2, secondInput, "trim must not follow the palette input (B1)")
        XCTAssertEqual(Array(pass2[ss2...(ss2 + 3)]), ["-ss", "00:00:05", "-to", "00:00:10"])
    }

    func testTrimIsInputSideOnMP4() {
        var options = Preset.mp4H264.options
        options.trim = Trim(start: "5")
        let args = FFmpegCommandBuilder.mp4Command(source: src, destination: dst,
                                                   options: options, audio: AudioPlan(mode: .none))
        XCTAssertLessThan(args.firstIndex(of: "-ss")!, args.firstIndex(of: "-i")!)
    }

    // MARK: B5 — per-codec CRF defaults

    func testPerCodecCRFDefaults() {
        XCTAssertEqual(VideoCodec.h264.defaultCRF, 23)
        XCTAssertEqual(VideoCodec.h265.defaultCRF, 28)
        XCTAssertEqual(VideoCodec.av1.defaultCRF, 32)
        let args = FFmpegCommandBuilder.mp4Command(
            source: src, destination: dst,
            options: ConversionOptions(format: .mp4(.h265)), audio: AudioPlan(mode: .none))
        let crfIndex = args.firstIndex(of: "-crf")!
        XCTAssertEqual(args[crfIndex + 1], "28")
    }

    // MARK: B6/B10 — audio plan

    func testAudioPlanStreamCopiesAAC() {
        XCTAssertEqual(AudioPlan.forSource(hasAudio: true, audioCodec: "aac").mode, .copy)
        XCTAssertEqual(AudioPlan.forSource(hasAudio: true, audioCodec: "pcm_s16le").mode, .transcodeAAC)
        XCTAssertEqual(AudioPlan.forSource(hasAudio: false, audioCodec: nil).mode, .none)
    }

    func testSilentSourceGetsAn() {
        let args = FFmpegCommandBuilder.mp4Command(
            source: src, destination: dst, options: Preset.mp4H264.options,
            audio: AudioPlan(mode: .none))
        XCTAssertTrue(args.contains("-an"))
        XCTAssertFalse(args.contains("aac"))
    }

    // MARK: B7 — AV1 path

    func testAV1UsesSVTWithoutLegacyFlags() {
        let args = FFmpegCommandBuilder.mp4Command(
            source: src, destination: dst,
            options: ConversionOptions(format: .mp4(.av1)), audio: AudioPlan(mode: .none))
        XCTAssertTrue(args.contains("libsvtav1"))
        XCTAssertFalse(args.contains("-strict"), "B7: -strict experimental is obsolete")
        XCTAssertFalse(args.contains("libaom-av1"))
        XCTAssertFalse(args.contains("-b:v"))
    }

    // MARK: scale variants

    func testFitWidthAndFitHeightFilters() {
        XCTAssertEqual(Scale.fitWidth(1280).filter, "scale=1280:-2")
        XCTAssertEqual(Scale.fitHeight(720).filter, "scale=-2:720")
        XCTAssertNil(Scale.original.filter)
    }
}
