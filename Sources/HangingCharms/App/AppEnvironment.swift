import AppKit
import HangingCharmsCore

/// The composition root: builds every service once and wires them together.
@MainActor
final class AppEnvironment {
    let store: SettingsStore
    let library: CharmLibrary
    let audio = AudioService()
    let overlay: OverlayController
    let customize: CustomizeWindowController
    private var statusItem: StatusItemController?
    private var hotKey: GlobalHotKey?

    init(store: SettingsStore = SettingsStore(), library: CharmLibrary = CharmLibrary()) {
        self.store = store
        self.library = library
        overlay = OverlayController(store: store, library: library, audio: audio)
        let overlay = self.overlay
        let model = CustomizeModel(store: store, library: library, audio: audio, charmsChanged: { overlay.charmsChanged() })
        customize = CustomizeWindowController(model: model)
    }

    func bootstrap() {
        CharmArtwork.connector = Connector.from(store.settings)
        // Settings that name a charm this build or this Mac no longer has fall back.
        store.update { $0.prune(validIDs: library.validIDs) }
        // The user may have removed the login item while we were not running.
        store.update { $0.launchAtLogin = LaunchAtLogin.isEnabled }
        store.observe { [weak self] old, new in
            guard new.launchAtLogin != old.launchAtLogin else { return }
            if !LaunchAtLogin.set(new.launchAtLogin) {
                self?.store.update { $0.launchAtLogin = LaunchAtLogin.isEnabled }
            }
        }

        overlay.openCustomize = { [weak self] page in self?.customize.show(page) }
        overlay.onImportPicture = { [weak self] url in
            self?.customize.model.pendingImport = url
            self?.customize.show(.create)
        }
        overlay.start()

        statusItem = StatusItemController(environment: self)
        hotKey = GlobalHotKey { [weak self] in self?.store.update { $0.isVisible.toggle() } }
        NSApp.mainMenu = MainMenu.make(environment: self)

        if !UserDefaults.standard.bool(forKey: "HangingCharms.didWelcome") {
            UserDefaults.standard.set(true, forKey: "HangingCharms.didWelcome")
            customize.show(.library)
        }
    }

    func shutdown() {
        overlay.stop()
        audio.stop()
        hotKey?.unregister()
    }
}

/// The menu bar item: the app's only permanent presence.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private unowned let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
        item.button?.image = Self.icon()
        item.button?.toolTip = "Hanging Charms"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    /// A pin, a cord and a charm, drawn as a template image.
    static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7.5, y: 0.5, width: 3, height: 3)).fill()
            let cord = NSBezierPath()
            cord.move(to: NSPoint(x: 9, y: 3))
            cord.curve(to: NSPoint(x: 10.5, y: 9), controlPoint1: NSPoint(x: 8, y: 5.5), controlPoint2: NSPoint(x: 10.5, y: 7))
            cord.lineWidth = 1.2
            cord.stroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: 9.2, y: 8.4, width: 2.6, height: 2.6))
            ring.lineWidth = 1
            ring.stroke()
            NSBezierPath(ovalIn: NSRect(x: 6.5, y: 10.5, width: 8, height: 7)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Hanging Charms"
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = environment.store.settings

        let toggle = NSMenuItem(title: settings.isVisible ? "Hide Charm" : "Show Charm", action: #selector(toggleVisible), keyEquivalent: "h")
        toggle.keyEquivalentModifierMask = [.control, .option, .command]
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        for page in [CustomizePage.library, .create, .appearance] {
            let item = NSMenuItem(title: page == .create ? "Create a Charm…" : "\(page.title)…", action: #selector(open(_:)), keyEquivalent: "")
            item.representedObject = page.rawValue
            item.target = self
            menu.addItem(item)
        }

        let ropes = NSMenuItem(title: "Rope", action: nil, keyEquivalent: "")
        let ropeMenu = NSMenu()
        for style in RopeStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: #selector(chooseRope(_:)), keyEquivalent: "")
            item.representedObject = style.rawValue
            item.state = settings.ropeStyle == style ? .on : .off
            item.target = self
            ropeMenu.addItem(item)
        }
        ropes.submenu = ropeMenu
        menu.addItem(ropes)
        menu.addItem(HangingMenus.hangFrom(store: environment.store))
        menu.addItem(HangingMenus.autoSwing(store: environment.store))
        menu.addItem(HangingMenus.breeze(store: environment.store))

        let sounds = NSMenuItem(title: "Charm Sounds", action: #selector(toggleSounds), keyEquivalent: "")
        sounds.state = settings.sounds ? .on : .off
        sounds.target = self
        menu.addItem(sounds)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = settings.launchAtLogin ? .on : .off
        login.target = self
        menu.addItem(login)

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Hanging Charms", action: #selector(open(_:)), keyEquivalent: "")
        about.representedObject = CustomizePage.about.rawValue
        about.target = self
        menu.addItem(about)
        menu.addItem(withTitle: "Quit Hanging Charms", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func toggleVisible() { environment.store.update { $0.isVisible.toggle() } }
    @objc private func toggleSounds() { environment.store.update { $0.sounds.toggle() } }
    @objc private func toggleLogin() { environment.store.update { $0.launchAtLogin.toggle() } }

    @objc private func open(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let page = CustomizePage(rawValue: raw) else { return }
        environment.customize.show(page)
    }

    @objc private func chooseRope(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = RopeStyle(rawValue: raw) else { return }
        environment.store.update { $0.ropeStyle = style }
    }
}

/// An accessory app shows no menu bar, but key equivalents (⌘C, ⌘V, ⌘W, ⌘Q) still go
/// through the main menu, so text fields in Customize need one to exist.
@MainActor
enum MainMenu {
    static func make(environment: AppEnvironment) -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Hanging Charms", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
