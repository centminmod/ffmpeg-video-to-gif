// Generates the VidConvert app icon as a .iconset directory — pure CoreGraphics,
// no external assets, deterministic output. Usage:
//
//   swift Tools/make-icon.swift <out.iconset>
//
// Big-Sur-style composition: a rounded-rect plate (~10% transparent margin,
// corner radius 22.5% of the plate — Apple's squircle approximation) filled with
// an indigo→violet vertical gradient; a white play-triangle merging into a
// rightward arrow (the conversion motif) and a film-strip bar of sprocket holes
// along the bottom. Drawn once at 1024×1024, then downscaled into the 10 sizes
// iconutil needs — one render keeps every size pixel-identical across runs.

import AppKit
import ImageIO

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else { die("usage: swift make-icon.swift <out.iconset>") }
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func makeContext(_ px: Int) -> CGContext {
    guard let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { die("CGContext creation failed (\(px)px)") }
    return ctx
}
func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
}

// ---- Master render at 1024×1024 (CG coordinates: origin bottom-left) ----
let S: CGFloat = 1024
let ctx = makeContext(Int(S))

// Plate: 10% transparent margin all around, 22.5% corner radius, vertical
// gradient deep indigo (top) → violet (bottom). Everything else clips to it.
let margin = S * 0.10
let plate = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let platePath = CGPath(
    roundedRect: plate, cornerWidth: plate.width * 0.225, cornerHeight: plate.width * 0.225,
    transform: nil)
ctx.addPath(platePath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: space,
    colors: [rgba(0x3A, 0x2E, 0x8C, 1), rgba(0x7A, 0x4D, 0xD8, 1)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(
    gradient, start: CGPoint(x: S / 2, y: plate.maxY), end: CGPoint(x: S / 2, y: plate.minY),
    options: [])

// Glyph: play triangle whose tip is submerged in the arrow shaft, so the union
// fills as one continuous mark (triangle → shaft → arrowhead = "play, converted").
// Sits above centre to leave room for the film strip below. Spans x 272…752
// (480 wide, centred on 512); the shaft starts at x 430, inside the triangle,
// so no notch appears where the two shapes meet.
let cy: CGFloat = 560
let glyph = CGMutablePath()
glyph.move(to: CGPoint(x: 272, y: cy + 150))                       // play triangle
glyph.addLine(to: CGPoint(x: 272, y: cy - 150))
glyph.addLine(to: CGPoint(x: 532, y: cy))
glyph.closeSubpath()
glyph.addRect(CGRect(x: 430, y: cy - 46, width: 184, height: 92))  // arrow shaft
glyph.move(to: CGPoint(x: 614, y: cy + 115))                       // arrowhead
glyph.addLine(to: CGPoint(x: 614, y: cy - 115))
glyph.addLine(to: CGPoint(x: 752, y: cy))
glyph.closeSubpath()
ctx.setFillColor(rgba(255, 255, 255, 1))
ctx.addPath(glyph)
ctx.fillPath()

// Film strip: two rows of sprocket holes along the plate bottom, white at 85%.
// x-range stays clear of the rounded corners at these heights.
ctx.setFillColor(rgba(255, 255, 255, 0.85))
let holeW: CGFloat = 40, holeH: CGFloat = 28, holes = 7
let stripLeft: CGFloat = 250, stripRight: CGFloat = 774
let gap = (stripRight - stripLeft - CGFloat(holes) * holeW) / CGFloat(holes - 1)
for rowY in [CGFloat(168), 232] {
    for i in 0..<holes {
        let x = stripLeft + CGFloat(i) * (holeW + gap)
        ctx.addPath(CGPath(
            roundedRect: CGRect(x: x, y: rowY - holeH / 2, width: holeW, height: holeH),
            cornerWidth: 9, cornerHeight: 9, transform: nil))
    }
}
ctx.fillPath()

guard let master = ctx.makeImage() else { die("makeImage failed") }

// ---- Downscale into the 10 iconset entries ----
let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in entries {
    let scaled = makeContext(px)
    scaled.interpolationQuality = .high
    scaled.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    guard let img = scaled.makeImage() else { die("makeImage failed (\(px)px)") }
    let url = outDir.appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { die("PNG destination failed: \(url.path)") }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { die("PNG write failed: \(url.path)") }
}
print("Wrote \(entries.count) PNGs to \(outDir.path)")
