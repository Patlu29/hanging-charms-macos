import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Launch at login

/// Launch at login through SMAppService. The stored flag is reconciled against the system
/// at launch, because the user can remove the login item in System Settings at any time.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// - Returns: Whether the change took effect.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return true
        } catch {
            NSLog("Hanging Charms: launch at login change failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Global hot key

/// One system-wide shortcut, registered with Carbon. Needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    fileprivate let action: () -> Void

    fileprivate static var current: GlobalHotKey?

    /// ⌃⌥⌘H by default.
    init(keyCode: UInt32 = UInt32(kVK_ANSI_H), modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey), action: @escaping () -> Void) {
        self.action = action
        GlobalHotKey.current = self

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { GlobalHotKey.current?.action() }
            return noErr
        }, 1, &spec, nil, &handler)

        let id = EventHotKeyID(signature: OSType(0x48434D53), id: 1) // 'HCMS'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &reference)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
        if GlobalHotKey.current === self { GlobalHotKey.current = nil }
    }

    static let displayString = "⌃⌥⌘H"
}

// MARK: - Full-screen detection

/// Tells whether the frontmost app is showing a full-screen window on a given display.
///
/// Window bounds and owners from CGWindowList need no Screen Recording permission; only
/// window titles do, and those are never read.
@MainActor
final class FullScreenWatcher {
    var onChange: ((Bool) -> Void)?
    private(set) var isFullScreen = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    var screenFrame: CGRect = .zero

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Full-screen transitions animate; look again once they settle.
                    self?.check()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.check() }
                }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        if isFullScreen {
            isFullScreen = false
            onChange?(false)
        }
    }

    func check() {
        let now = Self.frontmostAppIsFullScreen(on: screenFrame)
        guard now != isFullScreen else { return }
        isFullScreen = now
        onChange?(now)
    }

    static func frontmostAppIsFullScreen(on screenFrame: CGRect) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "com.apple.finder",
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        // CGWindowList uses top-left origin global coordinates.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let target = CGRect(x: screenFrame.minX, y: primaryHeight - screenFrame.maxY, width: screenFrame.width, height: screenFrame.height)

        for window in list {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            if abs(bounds.minX - target.minX) < 2, abs(bounds.minY - target.minY) < 2,
               abs(bounds.width - target.width) < 2, abs(bounds.height - target.height) < 2 {
                return true
            }
        }
        return false
    }
}
