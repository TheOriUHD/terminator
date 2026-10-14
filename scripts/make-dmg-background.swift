// Draws the installer window background: background.png (1x) and background@2x.png in the given folder.
// Usage: make-dmg-background <output folder>   (build-dmg.sh calls this for you)
import Cocoa

// Keep in step with the window and icon geometry in scripts/build-dmg.sh (points, y down from the top).
let width: CGFloat = 660, height: CGFloat = 400
let appX: CGFloat = 165, linkX: CGFloat = 495, iconsY: CGFloat = 190

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [
        CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, alpha,
    ])!
}

func draw(_ ctx: CGContext) {
    // CoreGraphics has y pointing up; convert from "points down from the top".
    func y(_ fromTop: CGFloat) -> CGFloat { height - fromTop }

    // Mid-tone slate backdrop. Finder draws the icon labels in black (Light Mode) or white (Dark Mode),
    // so the background has to stay readable with either.
    let backdrop = CGGradient(colorsSpace: cs, colors: [rgb(0x9a9fa9), rgb(0x767b86)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(backdrop, start: CGPoint(x: 0, y: height), end: .zero, options: [])

    // Arrow from the app towards Applications, in the app's red.
    let shaftLeft = appX + 92, headTip = linkX - 92, headLength: CGFloat = 46, half: CGFloat = 11, headHalf: CGFloat = 32
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: shaftLeft, y: y(iconsY) + half))
    arrow.addLine(to: CGPoint(x: headTip - headLength, y: y(iconsY) + half))
    arrow.addLine(to: CGPoint(x: headTip - headLength, y: y(iconsY) + headHalf))
    arrow.addLine(to: CGPoint(x: headTip, y: y(iconsY)))
    arrow.addLine(to: CGPoint(x: headTip - headLength, y: y(iconsY) - headHalf))
    arrow.addLine(to: CGPoint(x: headTip - headLength, y: y(iconsY) - half))
    arrow.addLine(to: CGPoint(x: shaftLeft, y: y(iconsY) - half))
    arrow.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: rgb(0xb0100a, 0.35))
    ctx.addPath(arrow)
    ctx.setFillColor(rgb(0xe8382a))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(arrow)
    ctx.clip()
    let red = CGGradient(colorsSpace: cs, colors: [rgb(0xff6a5c), rgb(0xd51a0e)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(red, start: CGPoint(x: 0, y: y(iconsY) + headHalf), end: CGPoint(x: 0, y: y(iconsY) - headHalf), options: [])
    ctx.restoreGState()

    // Text.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    func centered(_ text: String, font: NSFont, color: NSColor, baselineFromTop: CGFloat) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        string.draw(at: NSPoint(x: (width - string.size().width) / 2, y: y(baselineFromTop)))
    }
    centered("Drag Terminator into Applications", font: .systemFont(ofSize: 22, weight: .semibold),
             color: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1), baselineFromTop: 70)
    centered("You'll be asked to confirm before anything is quit.", font: .systemFont(ofSize: 13),
             color: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: 1), baselineFromTop: 96)
    NSGraphicsContext.restoreGraphicsState()
}

func writePNG(scale: Int, to url: URL) {
    let ctx = CGContext(data: nil, width: Int(width) * scale, height: Int(height) * scale, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    draw(ctx)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    // 72 dpi (1x) / 144 dpi (2x) is what lets tiffutil combine them into one Retina-aware image.
    let dpi = 72.0 * Double(scale)
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
writePNG(scale: 1, to: out.appendingPathComponent("background.png"))
writePNG(scale: 2, to: out.appendingPathComponent("background@2x.png"))
print("wrote background.png and background@2x.png to \(out.path)")
