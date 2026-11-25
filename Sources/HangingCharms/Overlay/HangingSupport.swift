import AppKit
import HangingCharmsCore

/// Finds the front window, for hanging the rope from it.
@MainActor
enum FrontWindow {
    /// The front app's main window on `screen`, in CGWindowList coordinates, or nil when
    /// our own app is in front or the front app has no window there.
    ///
    /// Window bounds and owners need no Screen Recording permission; titles do, and are
    /// never read.
    static func frame(on screen: NSScreen) -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenCG = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                              width: screen.frame.width, height: screen.frame.height)
        // The window list is front to back, so the first big window of the app wins.
        for window in list {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width >= 160, bounds.height >= 120,
                  bounds.intersects(screenCG) else { continue }
            return bounds
        }
        return nil
    }
}

/// The Hang From and Breeze submenus, shared by the menu bar and the charm's own menu.
@MainActor
enum HangingMenus {
    @MainActor
    private final class Target: NSObject {
        let store: SettingsStore
        init(store: SettingsStore) { self.store = store }
        @objc func hang(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let point = HangPoint(rawValue: raw) else { return }
            store.update { $0.hangPoint = point }
        }
        @objc func breeze(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let breeze = Breeze(rawValue: raw) else { return }
            store.update { $0.breeze = breeze }
        }
    }

    // Menu items hold their targets weakly, so keep one alive.
    private static var targets: [ObjectIdentifier: Target] = [:]

    private static func target(for store: SettingsStore) -> Target {
        let key = ObjectIdentifier(store)
        if let existing = targets[key] { return existing }
        let made = Target(store: store)
        targets[key] = made
        return made
    }

    static func hangFrom(store: SettingsStore) -> NSMenuItem {
        let item = NSMenuItem(title: "Hang From", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let target = target(for: store)
        for point in HangPoint.allCases {
            let entry = NSMenuItem(title: point.displayName, action: #selector(Target.hang(_:)), keyEquivalent: "")
            entry.representedObject = point.rawValue
            entry.state = store.settings.hangPoint == point ? .on : .off
            entry.target = target
            menu.addItem(entry)
        }
        item.submenu = menu
        return item
    }

    static func breeze(store: SettingsStore) -> NSMenuItem {
        let item = NSMenuItem(title: "Breeze", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let target = target(for: store)
        for breeze in Breeze.allCases {
            let entry = NSMenuItem(title: breeze.displayName, action: #selector(Target.breeze(_:)), keyEquivalent: "")
            entry.representedObject = breeze.rawValue
            entry.state = store.settings.breeze == breeze ? .on : .off
            entry.target = target
            menu.addItem(entry)
        }
        item.submenu = menu
        return item
    }
}
