import AppKit

final class LinePanel: NSPanel {
    static let height: CGFloat = 210

    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func restingFrame(on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.maxY - Self.height,
            width: screen.frame.width,
            height: Self.height
        )
    }
}
