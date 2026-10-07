import AppKit
import Carbon
import ServiceManagement
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ShotStore()
    private let defaults = UserDefaults.standard

    private var panel: LinePanel!
    private var rug: RugController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var watcher: FolderWatcher?
    private var ticker: Timer?

    private var shown = false
    private var shownScreen: NSScreen?
    private var openedByKey = false
    private var enteredSinceKey = false
    private var announceUntil = Date.distantPast
    private var dwellStart: (date: Date, point: NSPoint)?
    private var leftAt: Date?

    private var catching: Bool {
        get { defaults.bool(forKey: "catching") }
        set { defaults.set(newValue, forKey: "catching") }
    }

    private var style: Style {
        get { Style(rawValue: defaults.string(forKey: "style") ?? "") ?? .line }
        set { defaults.set(newValue.rawValue, forKey: "style") }
    }

    private var announcing: Bool {
        get { defaults.object(forKey: "announce") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "announce") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingView(rootView: LineView(store: store))
        host.sizingOptions = []
        panel = LinePanel(content: host)
        rug = RugController(store: store)
        if style == .rug { rug.show() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Clipline")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotKey = HotKey(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey) { [weak self] in
            MainActor.assumeIsolated { self?.toggleFromKey() }
        }

        if defaults.object(forKey: "catching") == nil {
            askToCatch()
        } else if catching {
            CaptureSettings.takeOver(into: store.folder)
        }
        watch()

        let ticker = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func applicationWillTerminate(_ notification: Notification) {
        CaptureSettings.restore()
    }

    private func askToCatch() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Hang new screenshots on the line?"
        alert.informativeText = "Clipline will save new screenshots to Pictures/Clipline and hide the floating thumbnail. Your previous settings come back when you quit or switch this off."
        alert.addButton(withTitle: "Catch Screenshots")
        alert.addButton(withTitle: "Not Now")
        catching = alert.runModal() == .alertFirstButtonReturn
        if catching {
            CaptureSettings.takeOver(into: store.folder)
        }
    }

    private func watch() {
        let directory = catching ? store.folder : CaptureSettings.location
        watcher = FolderWatcher(
            directory: directory,
            acceptAll: catching,
            onNew: { [weak self] url in
                MainActor.assumeIsolated { self?.caught(url) }
            },
            onChange: { [weak self] in
                MainActor.assumeIsolated { self?.store.reconcile() }
            }
        )
    }

    private func caught(_ url: URL) {
        store.add(url)
        guard announcing else { return }
        if style == .rug {
            rug.tuck()
            return
        }
        let screen = screenUnderMouse() ?? NSScreen.main
        guard let screen, !FullScreen.isActive(on: screen) else { return }
        announceUntil = Date().addingTimeInterval(2.6)
        if !shown { show(on: screen) }
    }

    private func toggleFromKey() {
        if style == .rug {
            rug.toggle()
        } else if shown {
            hide()
        } else if let screen = screenUnderMouse() ?? NSScreen.main {
            openedByKey = true
            enteredSinceKey = false
            show(on: screen)
        }
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private func inMenuBar(_ point: NSPoint, of screen: NSScreen) -> Bool {
        let bar = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        return point.y >= screen.frame.maxY - bar - 1
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        if style == .rug {
            rug.track(mouse: mouse)
            return
        }
        let now = Date()
        let buttonsDown = NSEvent.pressedMouseButtons != 0

        if shown {
            let overBar = shownScreen.map { inMenuBar(mouse, of: $0) && NSMouseInRect(mouse, $0.frame, false) } ?? false
            let inside = panel.frame.insetBy(dx: 0, dy: -2).contains(mouse) || overBar
            if inside {
                leftAt = nil
                if panel.frame.contains(mouse) { enteredSinceKey = true }
                return
            }
            let heldOpen = buttonsDown || now < announceUntil || (openedByKey && !enteredSinceKey)
            if heldOpen {
                leftAt = nil
                return
            }
            if let leftAt {
                if now.timeIntervalSince(leftAt) > 0.35 { hide() }
            } else {
                leftAt = now
            }
            return
        }

        guard !store.shots.isEmpty, !buttonsDown,
              let screen = screenUnderMouse(), inMenuBar(mouse, of: screen)
        else {
            dwellStart = nil
            return
        }

        if let start = dwellStart, hypot(mouse.x - start.point.x, mouse.y - start.point.y) < 8 {
            if now.timeIntervalSince(start.date) > 0.45 {
                dwellStart = nil
                if !FullScreen.isActive(on: screen) { show(on: screen) }
            }
        } else {
            dwellStart = (now, mouse)
        }
    }

    private func show(on screen: NSScreen) {
        shown = true
        shownScreen = screen
        leftAt = nil
        let frame = panel.restingFrame(on: screen)
        panel.setFrame(frame.offsetBy(dx: 0, dy: 26), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        shown = false
        openedByKey = false
        announceUntil = .distantPast
        let frame = panel.frame.offsetBy(dx: 0, dy: 26)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.shown else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = style == .rug ? "Fold Rug Back or Lay It Flat" : (shown ? "Hide Line" : "Show Line")
        let show = MenuAction(title) { [weak self] in self?.toggleFromKey() }
        show.keyEquivalent = "l"
        show.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(show)
        if style == .rug {
            menu.addItem(MenuAction("Lay Rug Flat") { [weak self] in self?.rug.layFlat() })
        }

        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let styles = NSMenu()
        for option in Style.allCases {
            let item = MenuAction(option.title) { [weak self] in self?.setStyle(option) }
            item.state = style == option ? .on : .off
            styles.addItem(item)
        }
        styleItem.submenu = styles
        menu.addItem(styleItem)
        menu.addItem(.separator())

        let catchItem = MenuAction("Catch New Screenshots") { [weak self] in self?.setCatching(!(self?.catching ?? false)) }
        catchItem.state = catching ? .on : .off
        menu.addItem(catchItem)

        let announceItem = MenuAction("Animate New Screenshots") { [weak self] in
            guard let self else { return }
            self.announcing.toggle()
        }
        announceItem.state = announcing ? .on : .off
        menu.addItem(announceItem)

        let expiry = NSMenuItem(title: "Clear Unpinned After", action: nil, keyEquivalent: "")
        let choices = NSMenu()
        for hours in ShotStore.expiryChoices {
            let item = MenuAction(Self.describe(hours: hours)) { [weak self] in self?.store.expiryHours = hours }
            item.state = store.expiryHours == hours ? .on : .off
            choices.addItem(item)
        }
        expiry.submenu = choices
        menu.addItem(expiry)
        menu.addItem(.separator())

        menu.addItem(MenuAction("Open Screenshots Folder") { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.catching ? self.store.folder : CaptureSettings.location)
        })
        let clear = MenuAction("Remove Unpinned Screenshots") { [weak self] in self?.store.clearUnpinned() }
        clear.isEnabled = store.shots.contains { !$0.pinned }
        menu.addItem(clear)
        menu.addItem(.separator())

        let login = MenuAction("Open at Login") {
            let service = SMAppService.mainApp
            if service.status == .enabled {
                try? service.unregister()
            } else {
                try? service.register()
            }
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit Clipline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func setStyle(_ new: Style) {
        guard new != style else { return }
        style = new
        if new == .rug {
            if shown { hide() }
            rug.show()
        } else {
            rug.hide()
        }
    }

    private func setCatching(_ on: Bool) {
        catching = on
        if on {
            CaptureSettings.takeOver(into: store.folder)
        } else {
            CaptureSettings.restore()
        }
        watch()
    }

    private static func describe(hours: Int) -> String {
        switch hours {
        case 0: "Never"
        case 1: "1 Hour"
        case 24: "1 Day"
        case 168: "1 Week"
        default: "\(hours) Hours"
        }
    }
}

enum Style: String, CaseIterable {
    case line
    case rug

    var title: String {
        switch self {
        case .line: "Washing Line"
        case .rug: "Rug"
        }
    }
}
