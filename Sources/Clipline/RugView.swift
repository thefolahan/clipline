import AppKit

final class RugView: NSView {
    var rugFrame: CGRect = .zero {
        didSet { needsDisplay = true }
    }
    var onMoved: ((CGRect) -> Void)?

    private var front: CGImage?
    private var back: CGImage?

    private var corner = 2
    private var lift = CGVector.zero
    private var velocity = CGVector.zero
    private var target = CGVector.zero
    private var ticker: Timer?

    private enum Grab {
        case peel(offset: CGVector)
        case move(offset: CGVector)
    }
    private var grab: Grab?
    private var teasing = false

    var isOpen: Bool { openness > 0.35 }

    init(size: CGSize) {
        super.init(frame: .zero)
        let art = RugArt.make(size: size, scale: 2)
        front = art?.front
        back = art?.back
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    private func cornerPoint(_ index: Int) -> CGPoint {
        let r = rugFrame
        switch index {
        case 0: return CGPoint(x: r.minX, y: r.minY)
        case 1: return CGPoint(x: r.maxX, y: r.minY)
        case 2: return CGPoint(x: r.maxX, y: r.maxY)
        default: return CGPoint(x: r.minX, y: r.maxY)
        }
    }

    private var grabbed: CGPoint { cornerPoint(corner) }
    private var opposite: CGPoint { cornerPoint((corner + 2) % 4) }
    private var tip: CGPoint { grabbed + lift }
    private var diagonal: CGVector { opposite - grabbed }
    private var openness: CGFloat { lift.length / max(diagonal.length, 1) }

    private struct Fold {
        let flat: [CGPoint]
        let lifted: [CGPoint]
        let flap: [CGPoint]
        let reflection: CGAffineTransform
        let middle: CGPoint
        let normal: CGVector
    }

    private var fold: Fold? {
        guard lift.length > 0.5 else { return nil }
        let middle = grabbed + lift * 0.5
        let normal = lift.normalized
        let rectangle = (0..<4).map(cornerPoint)
        let flat = clip(rectangle, middle: middle, normal: normal, keepFront: true)
        let lifted = clip(rectangle, middle: middle, normal: normal, keepFront: false)
        let offset = 2 * (middle.x * normal.dx + middle.y * normal.dy)
        let reflection = CGAffineTransform(
            a: 1 - 2 * normal.dx * normal.dx, b: -2 * normal.dx * normal.dy,
            c: -2 * normal.dx * normal.dy, d: 1 - 2 * normal.dy * normal.dy,
            tx: offset * normal.dx, ty: offset * normal.dy
        )
        let flap = lifted.map { $0.applying(reflection) }
        return Fold(flat: flat, lifted: lifted, flap: flap, reflection: reflection, middle: middle, normal: normal)
    }

    private func clip(_ polygon: [CGPoint], middle: CGPoint, normal: CGVector, keepFront: Bool) -> [CGPoint] {
        func side(_ p: CGPoint) -> CGFloat {
            let d = (p.x - middle.x) * normal.dx + (p.y - middle.y) * normal.dy
            return keepFront ? d : -d
        }
        var result: [CGPoint] = []
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            let sa = side(a)
            let sb = side(b)
            if sa >= 0 { result.append(a) }
            if (sa >= 0) != (sb >= 0) {
                let t = sa / (sa - sb)
                result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return result
    }

    private func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        if let first = points.first {
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
        return path
    }

    func covers(_ point: CGPoint) -> Bool {
        guard let fold else { return rugFrame.contains(point) }
        return path(fold.flat).contains(point) || path(fold.flap).contains(point)
    }

    func uncovered(_ point: CGPoint) -> Bool {
        guard let fold else { return false }
        return path(fold.lifted).contains(point) && !path(fold.flap).contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return covers(local) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let front, let back else { return }
        let fold = self.fold
        let flat = path(fold?.flat ?? (0..<4).map(cornerPoint))

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: CGColor(gray: 0, alpha: 0.45))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(flat)
        context.clip()
        context.draw(front, in: rugFrame)
        context.endTransparencyLayer()
        context.restoreGState()

        guard let fold, fold.flap.count > 2 else { return }
        let flap = path(fold.flap)

        context.saveGState()
        context.setShadow(offset: CGSize(width: fold.normal.dx * 6, height: fold.normal.dy * 6 - 4), blur: 16, color: CGColor(gray: 0, alpha: 0.5))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(flap)
        context.clip()
        context.concatenate(fold.reflection)
        context.draw(back, in: rugFrame)
        context.endTransparencyLayer()
        context.restoreGState()

        context.saveGState()
        context.addPath(flap)
        context.clip()
        let span = min(60, lift.length * 0.4)
        let start = fold.middle
        let end = CGPoint(x: start.x + fold.normal.dx * span, y: start.y + fold.normal.dy * span)
        let crease = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            CGColor(gray: 1, alpha: 0.22), CGColor(gray: 0, alpha: 0)
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(crease, start: start, end: end, options: [])
        context.restoreGState()
    }

    override func mouseMoved(with event: NSEvent) {
        guard grab == nil, !isOpen else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let near = nearestCorner(to: point, within: 64) {
            if !teasing || near != corner {
                if lift.length < 1 { corner = near }
                teasing = true
                animate(to: (opposite - grabbed) * 0.05)
            }
        } else if teasing {
            teasing = false
            animate(to: .zero)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        teasing = false
        if lift.length > 1, let fold, path(fold.flap).contains(point) || (point - tip).length < 60 {
            grab = .peel(offset: tip - point)
        } else if lift.length < 30, let near = nearestCorner(to: point, within: 64) {
            if near != corner {
                corner = near
                lift = .zero
            }
            grab = .peel(offset: tip - point)
        } else {
            grab = .move(offset: CGVector(dx: rugFrame.minX - point.x, dy: rugFrame.minY - point.y))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch grab {
        case .peel(let offset):
            var wanted = (point + offset) - grabbed
            let limit = diagonal.length * 1.05
            if wanted.length > limit { wanted = wanted.normalized * limit }
            animate(to: wanted, stiffness: 900, damping: 50)
        case .move(let offset):
            var origin = CGPoint(x: point.x + offset.dx, y: point.y + offset.dy)
            origin.x = min(max(origin.x, bounds.minX - rugFrame.width * 0.5), bounds.maxX - rugFrame.width * 0.5)
            origin.y = min(max(origin.y, bounds.minY - rugFrame.height * 0.5), bounds.maxY - rugFrame.height * 0.5)
            rugFrame.origin = origin
            onMoved?(rugFrame)
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .peel = grab {
            setOpen(openness > 0.35)
        }
        grab = nil
    }

    func setOpen(_ open: Bool) {
        animate(to: open ? diagonal * 1.0 : .zero, stiffness: open ? 140 : 190, damping: open ? 16 : 11)
    }

    func toggle() {
        if lift.length < 1 { corner = inwardCorner }
        setOpen(!isOpen)
    }

    private var inwardCorner: Int {
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        return (0..<4).min { a, b in
            (cornerPoint((a + 2) % 4) - middle).length < (cornerPoint((b + 2) % 4) - middle).length
        } ?? 2
    }

    func tuck() {
        guard grab == nil, !isOpen else { return }
        corner = inwardCorner
        lift = .zero
        animate(to: diagonal * 0.22, stiffness: 220, damping: 18)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.grab == nil, !self.isOpen else { return }
                self.animate(to: .zero, stiffness: 190, damping: 9)
            }
        }
    }

    private func nearestCorner(to point: CGPoint, within distance: CGFloat) -> Int? {
        (0..<4)
            .map { ($0, (cornerPoint($0) - point).length) }
            .filter { $0.1 < distance }
            .min { $0.1 < $1.1 }?.0
    }

    private var stiffness: CGFloat = 190
    private var damping: CGFloat = 12

    private func animate(to goal: CGVector, stiffness: CGFloat = 190, damping: CGFloat = 12) {
        target = goal
        self.stiffness = stiffness
        self.damping = damping
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func step() {
        let dt: CGFloat = 1.0 / 120
        let force = (target - lift) * stiffness - velocity * damping
        velocity = velocity + force * dt
        lift = lift + velocity * dt
        if (target - lift).length < 0.3 && velocity.length < 2 {
            lift = target
            velocity = .zero
            ticker?.invalidate()
            ticker = nil
        }
        needsDisplay = true
        onLift?()
    }

    var onLift: (() -> Void)?
}

extension CGVector {
    var length: CGFloat { (dx * dx + dy * dy).squareRoot() }
    var normalized: CGVector { length > 0 ? CGVector(dx: dx / length, dy: dy / length) : .zero }
    static func + (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy) }
    static func - (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx - b.dx, dy: a.dy - b.dy) }
    static func * (a: CGVector, s: CGFloat) -> CGVector { CGVector(dx: a.dx * s, dy: a.dy * s) }
}

extension CGPoint {
    static func + (p: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: p.x + v.dx, y: p.y + v.dy) }
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
}
