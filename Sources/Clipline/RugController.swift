import AppKit
import Combine

@MainActor
final class RugController {
    static let size = CGSize(width: 620, height: 390)

    private let store: ShotStore
    private let panel: NSPanel
    private let container = RugContainer()
    private let rug = RugView(size: RugController.size)
    private var prints: [URL: PrintView] = [:]
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

        rug.autoresizingMask = [.width, .height]
        container.addSubview(rug)
        rug.onMoved = { [weak self] frame in
            UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: "rugOrigin")
            self?.arrange()
        }

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
        rug.frame = container.bounds

        let saved = UserDefaults.standard.string(forKey: "rugOrigin").map(NSPointFromString)
        let fallback = CGPoint(x: 80, y: 80)
        var origin = saved ?? fallback
        if !container.bounds.insetBy(dx: -Self.size.width / 2, dy: -Self.size.height / 2).contains(origin) {
            origin = fallback
        }
        rug.rugFrame = CGRect(origin: origin, size: Self.size)
        arrange()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        panel.ignoresMouseEvents = true
    }

    func toggle() {
        rug.toggle()
    }

    func tuck() {
        rug.tuck()
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
            container.addSubview(view, positioned: .below, relativeTo: rug)
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
        let rugFrame = rug.rugFrame.insetBy(dx: 60, dy: 50)
        for (url, view) in prints {
            let size = Self.printSize(for: view.image)
            var random = SeededRandom(seed: url.lastPathComponent.unicodeScalars.reduce(1_469_598_103_934_665_603) { ($0 ^ UInt64($1.value)) &* 1_099_511_628_211 })
            let center = CGPoint(
                x: rugFrame.minX + random.next(in: 0...1) * rugFrame.width,
                y: rugFrame.minY + random.next(in: 0...1) * rugFrame.height
            )
            view.frameCenterRotation = 0
            view.frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
            view.frameCenterRotation = random.next(in: -14...14)
        }
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
