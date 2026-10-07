import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
context.addPath(tilePath)
context.setFillColor(NSColor.white.cgColor)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath)
context.clip()
let sky = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(red: 0.47, green: 0.74, blue: 0.98, alpha: 1).cgColor,
        NSColor(red: 0.20, green: 0.45, blue: 0.90, alpha: 1).cgColor
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(sky, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

func ropeY(_ x: CGFloat) -> CGFloat {
    let t = (x - tile.minX) / tile.width
    return 690 - 4 * 70 * t * (1 - t)
}

let rope = CGMutablePath()
rope.move(to: CGPoint(x: tile.minX, y: ropeY(tile.minX)))
for x in stride(from: tile.minX, through: tile.maxX, by: 4) {
    rope.addLine(to: CGPoint(x: x, y: ropeY(x)))
}
context.addPath(rope)
context.setLineWidth(16)
context.setLineCap(.round)
context.setStrokeColor(NSColor(red: 0.95, green: 0.89, blue: 0.79, alpha: 1).cgColor)
context.strokePath()
context.addPath(rope)
context.setLineDash(phase: 0, lengths: [10, 16])
context.setLineWidth(16)
context.setStrokeColor(NSColor(red: 0.72, green: 0.61, blue: 0.47, alpha: 1).cgColor)
context.strokePath()
context.setLineDash(phase: 0, lengths: [])

func card(centerX: CGFloat, width: CGFloat, height: CGFloat, angle: CGFloat, art: NSColor, peg: (NSColor, NSColor)) {
    let top = ropeY(centerX) - 14
    context.saveGState()
    context.translateBy(x: centerX, y: top)
    context.rotate(by: angle * .pi / 180)

    let frame = CGRect(x: -width / 2, y: -height, width: width, height: height)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.setFillColor(NSColor(white: 0.99, alpha: 1).cgColor)
    context.fill(frame)
    context.restoreGState()

    let border: CGFloat = 20
    let photo = CGRect(x: frame.minX + border, y: frame.minY + 62, width: width - border * 2, height: height - 62 - border)
    context.setFillColor(art.cgColor)
    context.fill(photo)
    context.setFillColor(NSColor.white.withAlphaComponent(0.55).cgColor)
    for row in 0..<3 {
        let bar = CGRect(x: photo.minX + 22, y: photo.maxY - 48 - CGFloat(row) * 40, width: (photo.width - 44) * (row == 2 ? 0.55 : 1), height: 18)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: 9, cornerHeight: 9, transform: nil))
        context.fillPath()
    }

    let pegRect = CGRect(x: -20, y: -58, width: 40, height: 104)
    let pegGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [peg.0.cgColor, peg.1.cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -5), blur: 8, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(CGPath(roundedRect: pegRect, cornerWidth: 10, cornerHeight: 10, transform: nil))
    context.clip()
    context.drawLinearGradient(pegGradient, start: CGPoint(x: pegRect.minX, y: 0), end: CGPoint(x: pegRect.maxX, y: 0), options: [])
    context.restoreGState()
    context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
    context.fill(CGRect(x: -2, y: pegRect.minY + 6, width: 4, height: pegRect.height - 12))
    context.setFillColor(NSColor(white: 0.8, alpha: 1).cgColor)
    context.addPath(CGPath(roundedRect: CGRect(x: -26, y: -2, width: 52, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil))
    context.fillPath()

    context.restoreGState()
}

let wood = (NSColor(red: 0.88, green: 0.72, blue: 0.52, alpha: 1), NSColor(red: 0.64, green: 0.47, blue: 0.29, alpha: 1))
let red = (NSColor(red: 0.96, green: 0.36, blue: 0.31, alpha: 1), NSColor(red: 0.72, green: 0.16, blue: 0.15, alpha: 1))
card(centerX: 340, width: 300, height: 360, angle: 5, art: NSColor(red: 0.98, green: 0.62, blue: 0.27, alpha: 1), peg: wood)
card(centerX: 670, width: 300, height: 300, angle: -4, art: NSColor(red: 0.29, green: 0.78, blue: 0.62, alpha: 1), peg: red)

context.restoreGState()

let png = bitmap.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: output))
