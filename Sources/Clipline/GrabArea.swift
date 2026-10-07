import AppKit
import SwiftUI

struct ShotActions {
    var copy: () -> Void
    var copyText: () -> Bool
    var togglePin: () -> Void
    var open: () -> Void
    var reveal: () -> Void
    var trash: () -> Void
    var dragEnded: () -> Void
}

struct GrabArea: NSViewRepresentable {
    let shot: Shot
    let image: NSImage?
    let actions: ShotActions
    let onHover: (Bool) -> Void
    let onFeedback: (String) -> Void

    func makeNSView(context: Context) -> GrabView {
        GrabView()
    }

    func updateNSView(_ view: GrabView, context: Context) {
        view.shot = shot
        view.image = image
        view.actions = actions
        view.onHover = onHover
        view.onFeedback = onFeedback
    }
}

final class GrabView: NSView, NSDraggingSource {
    var shot: Shot?
    var image: NSImage?
    var actions: ShotActions?
    var onHover: ((Bool) -> Void)?
    var onFeedback: ((String) -> Void)?

    private var pressedAt: NSEvent?
    private var holdTimer: Timer?
    private var held = false
    private var dragging = false
    private var hovering = false

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        onHover?(false)
    }

    private var closeRect: NSRect {
        NSRect(x: bounds.maxX - 30, y: 0, width: 30, height: 30)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hovering && closeRect.contains(point) {
            actions?.trash()
            return
        }

        pressedAt = event
        held = false
        dragging = false
        holdTimer?.invalidate()
        let timer = Timer(timeInterval: 0.55, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.dragging else { return }
                self.held = true
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                self.actions?.togglePin()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressedAt, !dragging, !held, let url = shot?.url else { return }
        let a = start.locationInWindow
        let b = event.locationInWindow
        guard hypot(b.x - a.x, b.y - a.y) > 4 else { return }

        holdTimer?.invalidate()
        dragging = true

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        let session = beginDraggingSession(with: [item], event: start, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        defer { pressedAt = nil }
        guard pressedAt != nil, !dragging, !held else { return }

        if event.clickCount >= 2 {
            actions?.open()
        } else if event.modifierFlags.contains(.option) {
            onFeedback?(actions?.copyText() == true ? "Text copied" : "No text found")
        } else {
            actions?.copy()
            onFeedback?("Copied")
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let shot else { return nil }
        let menu = NSMenu()
        menu.addItem(MenuAction("Copy Image") { [weak self] in
            self?.actions?.copy()
            self?.onFeedback?("Copied")
        })
        let text = MenuAction(shot.text == nil ? "Reading Text" : "Copy Text") { [weak self] in
            self?.onFeedback?(self?.actions?.copyText() == true ? "Text copied" : "No text found")
        }
        text.isEnabled = shot.text?.isEmpty == false
        menu.addItem(text)
        menu.addItem(.separator())
        menu.addItem(MenuAction(shot.pinned ? "Unpin" : "Pin to Line") { [weak self] in self?.actions?.togglePin() })
        menu.addItem(MenuAction("Open in Preview") { [weak self] in self?.actions?.open() })
        menu.addItem(MenuAction("Show in Finder") { [weak self] in self?.actions?.reveal() })
        menu.addItem(.separator())
        menu.addItem(MenuAction("Move to Trash") { [weak self] in self?.actions?.trash() })
        return menu
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .generic, .delete] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        if operation.contains(.delete), let url = shot?.url, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        actions?.dragEnded()
    }
}

final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
