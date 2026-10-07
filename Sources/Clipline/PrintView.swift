import AppKit

final class PrintView: GrabView {
    private let picture = CALayer()
    private let close = CATextLayer()
    private let toast = CATextLayer()
    private let pin = CALayer()

    static let border: CGFloat = 5

    init(shot: Shot, image: NSImage?, actions: ShotActions) {
        super.init(frame: .zero)
        self.shot = shot
        self.image = image
        self.actions = actions
        wantsLayer = true

        guard let layer else { return }
        layer.backgroundColor = CGColor(gray: 0.985, alpha: 1)
        layer.cornerRadius = 2
        layer.shadowColor = .black
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: -2)

        picture.contents = image
        picture.contentsGravity = .resizeAspectFill
        picture.masksToBounds = true
        picture.cornerRadius = 1.5
        layer.addSublayer(picture)

        pin.backgroundColor = CGColor(red: 0.85, green: 0.2, blue: 0.19, alpha: 1)
        pin.cornerRadius = 5
        pin.shadowColor = .black
        pin.shadowOpacity = 0.4
        pin.shadowRadius = 1.5
        pin.shadowOffset = CGSize(width: 0, height: -1)
        layer.addSublayer(pin)

        close.string = "✕"
        close.alignmentMode = .center
        close.fontSize = 10
        close.foregroundColor = .white
        close.backgroundColor = CGColor(gray: 0, alpha: 0.62)
        close.cornerRadius = 9
        close.opacity = 0
        layer.addSublayer(close)

        toast.alignmentMode = .center
        toast.fontSize = 11
        toast.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        toast.foregroundColor = .white
        toast.backgroundColor = CGColor(gray: 0, alpha: 0.72)
        toast.cornerRadius = 10
        toast.opacity = 0
        layer.addSublayer(toast)

        onFeedback = { [weak self] message in self?.flash(message) }
        update(shot: shot)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(shot: Shot) {
        self.shot = shot
        pin.isHidden = !shot.pinned
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        [picture, close, toast, pin].forEach { $0.contentsScale = scale }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = bounds.insetBy(dx: Self.border, dy: Self.border)
        close.frame = CGRect(x: bounds.maxX - 26, y: 8, width: 18, height: 18)
        pin.frame = CGRect(x: bounds.midX - 5, y: 1, width: 10, height: 10)
        toast.frame = CGRect(x: bounds.midX - 44, y: bounds.midY - 10, width: 88, height: 20)
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        close.opacity = 1
        layer?.shadowRadius = 9
        layer?.shadowOpacity = 0.5
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        close.opacity = 0
        layer?.shadowRadius = 5
        layer?.shadowOpacity = 0.35
    }

    private func flash(_ message: String) {
        toast.string = message
        toast.opacity = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            MainActor.assumeIsolated {
                if (self?.toast.string as? String) == message { self?.toast.opacity = 0 }
            }
        }
    }
}
