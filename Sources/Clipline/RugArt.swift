import AppKit

enum RugArt {
    static let fringe: CGFloat = 14

    private static let red = CGColor(red: 0.56, green: 0.11, blue: 0.11, alpha: 1)
    private static let deepRed = CGColor(red: 0.40, green: 0.06, blue: 0.07, alpha: 1)
    private static let navy = CGColor(red: 0.11, green: 0.14, blue: 0.26, alpha: 1)
    private static let cream = CGColor(red: 0.92, green: 0.85, blue: 0.71, alpha: 1)
    private static let gold = CGColor(red: 0.78, green: 0.60, blue: 0.29, alpha: 1)

    static func make(size: CGSize, scale: CGFloat) -> (front: CGImage, back: CGImage)? {
        guard let front = render(size: size, scale: scale, draw: { drawFront(in: $0, size: size) }),
              let back = render(size: size, scale: scale, draw: { context in
                  context.draw(front, in: CGRect(origin: .zero, size: size))
                  context.setBlendMode(.saturation)
                  context.setFillColor(CGColor(gray: 0.5, alpha: 0.55))
                  context.fill(CGRect(origin: .zero, size: size))
                  context.setBlendMode(.multiply)
                  context.setFillColor(CGColor(red: 0.55, green: 0.47, blue: 0.43, alpha: 1))
                  context.fill(CGRect(origin: .zero, size: size))
                  context.setBlendMode(.destinationIn)
                  context.draw(front, in: CGRect(origin: .zero, size: size))
              })
        else { return nil }
        return (front, back)
    }

    private static func render(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(size.width * scale),
            height: Int(size.height * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        draw(context)
        return context.makeImage()
    }

    private static func drawFront(in context: CGContext, size: CGSize) {
        var random = SeededRandom(seed: 42)
        let body = CGRect(x: fringe, y: 0, width: size.width - fringe * 2, height: size.height)

        context.setStrokeColor(cream)
        context.setLineCap(.round)
        for side in [body.minX, body.maxX] {
            let outward: CGFloat = side == body.minX ? -1 : 1
            var y: CGFloat = 4
            while y < size.height - 4 {
                let length = fringe - random.next(in: 0...4)
                context.setLineWidth(random.next(in: 1.2...2))
                context.move(to: CGPoint(x: side, y: y))
                context.addLine(to: CGPoint(x: side + outward * length, y: y + random.next(in: -1.5...1.5)))
                context.strokePath()
                y += 3.4
            }
        }

        context.setFillColor(red)
        context.fill(body)

        let outer = body.insetBy(dx: 2, dy: 2)
        band(context, outer, width: 26, fill: navy)
        motifs(context, along: outer.insetBy(dx: 13, dy: 13), spacing: 22) { point in
            diamond(context, at: point, radius: 7, color: cream)
            dot(context, at: point, radius: 2.4, color: red)
        }

        var inner = outer.insetBy(dx: 26, dy: 26)
        band(context, inner, width: 3, fill: cream)
        inner = inner.insetBy(dx: 3, dy: 3)
        band(context, inner, width: 2, fill: gold)
        inner = inner.insetBy(dx: 2, dy: 2)
        band(context, inner, width: 13, fill: deepRed)
        motifs(context, along: inner.insetBy(dx: 6.5, dy: 6.5), spacing: 15) { point in
            dot(context, at: point, radius: 3, color: navy)
            dot(context, at: point, radius: 1.2, color: cream)
        }
        inner = inner.insetBy(dx: 13, dy: 13)
        band(context, inner, width: 2, fill: cream)
        let field = inner.insetBy(dx: 2, dy: 2)

        context.saveGState()
        context.clip(to: field)

        let center = CGPoint(x: field.midX, y: field.midY)
        for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
            let corner = CGPoint(x: sx < 0 ? field.minX : field.maxX, y: sy < 0 ? field.minY : field.maxY)
            ellipse(context, center: corner, rx: field.width * 0.2, ry: field.height * 0.3, fill: navy, stroke: cream)
            ellipse(context, center: corner, rx: field.width * 0.13, ry: field.height * 0.2, fill: deepRed, stroke: gold)
        }

        var flowers = SeededRandom(seed: 7)
        for _ in 0..<26 {
            let dx = flowers.next(in: 0.08...0.48) * field.width
            let dy = flowers.next(in: 0.06...0.47) * field.height
            let radius = flowers.next(in: 2.2...4.2)
            let tone = flowers.next(in: 0...1) > 0.5 ? cream : gold
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                let point = CGPoint(x: center.x + sx * dx, y: center.y + sy * dy)
                flower(context, at: point, radius: radius, petals: tone)
            }
        }

        let mw = field.width * 0.27
        let mh = field.height * 0.46
        for (scale, fill, stroke) in [(1.0, navy, cream), (0.74, red, gold), (0.5, cream, navy), (0.3, navy, cream)] {
            lozenge(context, center: center, rx: mw * scale, ry: mh * scale, fill: fill, stroke: stroke)
        }
        for sign in [-1.0, 1.0] {
            let tip = CGPoint(x: center.x + sign * (mw + 12), y: center.y)
            diamond(context, at: tip, radius: 10, color: navy)
            diamond(context, at: tip, radius: 5, color: cream)
        }
        star(context, center: center, outer: mh * 0.2, inner: mh * 0.1, points: 8, color: red)
        dot(context, at: center, radius: mh * 0.06, color: cream)
        context.restoreGState()

        var weave = SeededRandom(seed: 99)
        context.setLineWidth(0.6)
        for _ in 0..<5200 {
            let x = weave.next(in: body.minX...body.maxX)
            let y = weave.next(in: body.minY...body.maxY)
            let light = weave.next(in: 0...1) > 0.5
            context.setStrokeColor(CGColor(gray: light ? 1 : 0, alpha: light ? 0.07 : 0.1))
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x + 2.2, y: y))
            context.strokePath()
        }
    }

    private static func band(_ context: CGContext, _ rect: CGRect, width: CGFloat, fill: CGColor) {
        let path = CGMutablePath()
        path.addRect(rect)
        path.addRect(rect.insetBy(dx: width, dy: width))
        context.addPath(path)
        context.setFillColor(fill)
        context.fillPath(using: .evenOdd)
    }

    private static func motifs(_ context: CGContext, along rect: CGRect, spacing: CGFloat, draw: (CGPoint) -> Void) {
        var x = rect.minX
        while x <= rect.maxX {
            draw(CGPoint(x: x, y: rect.minY))
            draw(CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY + spacing
        while y < rect.maxY {
            draw(CGPoint(x: rect.minX, y: y))
            draw(CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
    }

    private static func dot(_ context: CGContext, at point: CGPoint, radius: CGFloat, color: CGColor) {
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }

    private static func diamond(_ context: CGContext, at point: CGPoint, radius: CGFloat, color: CGColor) {
        lozenge(context, center: point, rx: radius, ry: radius, fill: color, stroke: nil)
    }

    private static func lozenge(_ context: CGContext, center: CGPoint, rx: CGFloat, ry: CGFloat, fill: CGColor, stroke: CGColor?) {
        context.beginPath()
        context.move(to: CGPoint(x: center.x - rx, y: center.y))
        context.addLine(to: CGPoint(x: center.x, y: center.y + ry))
        context.addLine(to: CGPoint(x: center.x + rx, y: center.y))
        context.addLine(to: CGPoint(x: center.x, y: center.y - ry))
        context.closePath()
        context.setFillColor(fill)
        if let stroke {
            context.setStrokeColor(stroke)
            context.setLineWidth(2.5)
            context.drawPath(using: .fillStroke)
        } else {
            context.fillPath()
        }
    }

    private static func ellipse(_ context: CGContext, center: CGPoint, rx: CGFloat, ry: CGFloat, fill: CGColor, stroke: CGColor) {
        context.addEllipse(in: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2))
        context.setFillColor(fill)
        context.setStrokeColor(stroke)
        context.setLineWidth(2.5)
        context.drawPath(using: .fillStroke)
    }

    private static func star(_ context: CGContext, center: CGPoint, outer: CGFloat, inner: CGFloat, points: Int, color: CGColor) {
        context.beginPath()
        for i in 0..<(points * 2) {
            let angle = CGFloat(i) * .pi / CGFloat(points)
            let radius = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            i == 0 ? context.move(to: point) : context.addLine(to: point)
        }
        context.closePath()
        context.setFillColor(color)
        context.fillPath()
    }

    private static func flower(_ context: CGContext, at point: CGPoint, radius: CGFloat, petals: CGColor) {
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            dot(context, at: CGPoint(x: point.x + cos(angle) * radius, y: point.y + sin(angle) * radius), radius: radius * 0.6, color: petals)
        }
        dot(context, at: point, radius: radius * 0.55, color: navy)
    }
}

struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        let unit = CGFloat(state % 1_000_000) / 1_000_000
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
