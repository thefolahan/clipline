import AppKit
import Combine

@MainActor
final class RugController {
    private let store: ShotStore
    private let panel: NSPanel
    private let container = RugContainer()
    private var rug: RugScene!
    private let shadow = CAShapeLayer()
    private let shadowView = PassThroughView()
    private var prints: [URL: PrintView] = [:]
    private var spots: [String: [Double]] = UserDefaults.standard.dictionary(forKey: "rugSpots") as? [String: [Double]] ?? [:]
    private var subscription: AnyCancellable?

    init(store: ShotStore) {
        self.store = store
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = container

        subscription = store.$shots.sink { [weak self] shots in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.sync(shots) }
            }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(screen.visibleFrame, display: false)
        container.frame = CGRect(origin: .zero, size: screen.visibleFrame.size)

        if rug == nil {
            let saved = UserDefaults.standard.string(forKey: "rugCenter").map(NSPointFromString)
            var center = saved ?? CGPoint(x: 420, y: 300)
            if !container.bounds.contains(center) { center = CGPoint(x: 420, y: 300) }
            rug = RugScene(frame: container.bounds, center: SIMD2(Float(center.x), Float(center.y)))
            rug.autoresizingMask = [.width, .height]
            shadowView.frame = container.bounds
            shadowView.autoresizingMask = [.width, .height]
            shadowView.wantsLayer = true
            shadow.fillColor = NSColor(white: 0, alpha: 0.01).cgColor
            shadow.shadowColor = .black
            shadow.shadowOpacity = 0.5
            shadow.shadowRadius = 9
            shadow.shadowOffset = .zero
            shadowView.layer?.addSublayer(shadow)
            container.addSubview(shadowView)
            rug.onOutline = { [weak self] path in
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self?.shadow.path = path
                self?.shadow.shadowPath = path
                CATransaction.commit()
            }
            rug.onRest = { offset in
                UserDefaults.standard.set(NSStringFromPoint(CGPoint(x: CGFloat(offset.x), y: CGFloat(offset.y))), forKey: "rugCenter")
            }
            container.addSubview(rug)
            rug.refreshOutline()
            prints.values.forEach { container.addSubview($0, positioned: .below, relativeTo: shadowView) }
        }
        arrange()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        panel.ignoresMouseEvents = true
    }

    func toggle() {
        rug?.toggle()
    }

    func tuck() {
        rug?.tuck()
    }

    func layFlat() {
        rug?.layFlat()
    }

    func track(mouse: NSPoint) {
        guard panel.isVisible else { return }
        if !panel.ignoresMouseEvents && NSEvent.pressedMouseButtons != 0 { return }
        let point = container.convert(panel.convertPoint(fromScreen: mouse), from: nil)
        panel.ignoresMouseEvents = container.hitTest(point) == nil
    }

    private func sync(_ shots: [Shot]) {
        let live = Set(shots.map(\.url))
        for (url, view) in prints where !live.contains(url) {
            view.removeFromSuperview()
            prints[url] = nil
        }
        for shot in shots.reversed() {
            if let existing = prints[shot.url] {
                existing.update(shot: shot)
                existing.actions = store.actions(for: shot)
                continue
            }
            let view = PrintView(shot: shot, image: store.thumbnail(for: shot), actions: store.actions(for: shot))
            if rug != nil {
                container.addSubview(view, positioned: .below, relativeTo: shadowView)
            } else {
                container.addSubview(view)
            }
            prints[shot.url] = view
            if panel.isVisible {
                view.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.45
                    view.animator().alphaValue = 1
                }
            }
        }
        arrange()
    }

    private func arrange() {
        let area = (rug?.footprint() ?? CGRect(x: 110, y: 105, width: 620, height: 390)).insetBy(dx: 70, dy: 60)
        var changed = false
        for (url, view) in prints {
            let name = url.lastPathComponent
            if spots[name] == nil {
                var random = SeededRandom(seed: name.unicodeScalars.reduce(1_469_598_103_934_665_603) { ($0 ^ UInt64($1.value)) &* 1_099_511_628_211 })
                spots[name] = [
                    Double(area.minX + random.next(in: 0...1) * area.width),
                    Double(area.minY + random.next(in: 0...1) * area.height),
                    Double(random.next(in: -14...14))
                ]
                changed = true
            }
            guard let spot = spots[name], spot.count == 3 else { continue }
            let size = Self.printSize(for: view.image)
            view.frameCenterRotation = 0
            view.frame = CGRect(x: spot[0] - size.width / 2, y: spot[1] - size.height / 2, width: size.width, height: size.height)
            view.frameCenterRotation = spot[2]
        }
        let live = Set(prints.keys.map(\.lastPathComponent))
        if spots.keys.contains(where: { !live.contains($0) }) {
            spots = spots.filter { live.contains($0.key) }
            changed = true
        }
        if changed { UserDefaults.standard.set(spots, forKey: "rugSpots") }
    }

    private static func printSize(for image: NSImage?) -> CGSize {
        let longest: CGFloat = 150
        guard let size = image?.size, size.width > 0, size.height > 0 else {
            return CGSize(width: longest, height: longest * 0.66)
        }
        let scale = longest / max(size.width, size.height)
        return CGSize(width: size.width * scale + PrintView.border * 2, height: size.height * scale + PrintView.border * 2)
    }
}

final class RugContainer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
