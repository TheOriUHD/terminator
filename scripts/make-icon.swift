// Draws the Terminator app icon and writes a Terminator.iconset folder of PNGs.
//
//   swiftc -O scripts/make-icon.swift -o /tmp/make-icon
//   /tmp/make-icon /tmp/Terminator.iconset
//   iconutil -c icns /tmp/Terminator.iconset -o AppIcon.icns
import Cocoa

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [
        CGFloat((hex >> 16) & 0xff) / 255,
        CGFloat((hex >> 8) & 0xff) / 255,
        CGFloat(hex & 0xff) / 255,
        alpha,
    ])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}

// macOS-style squircle (superellipse) tile.
func squircle(center: CGPoint, half: CGFloat, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = center.x + half * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = center.y + half * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

// Everything is drawn on a 1024 x 1024 canvas (y points up).
func drawIcon(_ ctx: CGContext) {
    let c = CGPoint(x: 512, y: 512)
    let shape = squircle(center: c, half: 412)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x000000, 0.45))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0x15161a))
    ctx.fillPath()
    ctx.restoreGState()

    // Tile body.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    ctx.drawLinearGradient(gradient([(0, rgb(0x0c0d10)), (1, rgb(0x3a3d45))]),
                           start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

    // Red ambient glow behind the reticle.
    ctx.drawRadialGradient(gradient([(0, rgb(0xff3b2f, 0.34)), (1, rgb(0xff3b2f, 0))]),
                           startCenter: c, startRadius: 0, endCenter: c, endRadius: 520, options: [])

    // Faint grid of app tiles - the things being targeted.
    let tile: CGFloat = 170, gap: CGFloat = 36
    let origin = 512 - (3 * tile + 2 * gap) / 2
    for row in 0..<3 {
        for col in 0..<3 {
            let r = CGRect(x: origin + CGFloat(col) * (tile + gap), y: origin + CGFloat(row) * (tile + gap),
                           width: tile, height: tile)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 40, cornerHeight: 40, transform: nil))
        }
    }
    ctx.setFillColor(rgb(0xffffff, 0.07))
    ctx.fillPath()

    // Targeting reticle: ring, four crosshair ticks and a glowing centre.
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: 512 - 232, y: 512 - 232, width: 464, height: 464))
    let ticks = CGMutablePath()
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] as [(CGFloat, CGFloat)] {
        ticks.move(to: CGPoint(x: 512 + dx * 112, y: 512 + dy * 112))
        ticks.addLine(to: CGPoint(x: 512 + dx * 338, y: 512 + dy * 338))
    }
    let pieces: [CGPath] = [
        ring.copy(strokingWithWidth: 42, lineCap: .butt, lineJoin: .round, miterLimit: 10),
        ticks.copy(strokingWithWidth: 36, lineCap: .round, lineJoin: .round, miterLimit: 10),
        CGPath(ellipseIn: CGRect(x: 512 - 58, y: 512 - 58, width: 116, height: 116), transform: nil),
    ]

    // Glow.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 70, color: rgb(0xff2a1a, 0.95))
    ctx.setFillColor(rgb(0xff3a2c))
    for p in pieces { ctx.addPath(p); ctx.fillPath() }
    ctx.restoreGState()

    // Red metal gradient over the same shapes.
    let red = gradient([(0, rgb(0xff7468)), (0.5, rgb(0xf2361f)), (1, rgb(0xb00f09))])
    for p in pieces {
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        ctx.drawLinearGradient(red, start: CGPoint(x: 512, y: 860), end: CGPoint(x: 512, y: 164), options: [])
        ctx.restoreGState()
    }

    // Hot core.
    ctx.addEllipse(in: CGRect(x: 512 - 26, y: 512 - 26, width: 52, height: 52))
    ctx.setFillColor(rgb(0xffe2dc))
    ctx.fillPath()

    ctx.restoreGState()

    // Rim light along the top edge of the tile.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.addPath(shape.copy(strokingWithWidth: 8, lineCap: .butt, lineJoin: .round, miterLimit: 10))
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0xffffff, 0)), (0.5, rgb(0xffffff, 0.04)), (1, rgb(0xffffff, 0.30))]),
                           start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()
}

func renderMaster() -> CGImage {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(ctx)
    return ctx.makeImage()!
}

func scaled(_ image: CGImage, to size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Terminator.iconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let master = renderMaster()
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in sizes {
    writePNG(size == 1024 ? master : scaled(master, to: size), to: outDir.appendingPathComponent(name + ".png"))
}
print("wrote \(sizes.count) PNGs to \(outDir.path)")
