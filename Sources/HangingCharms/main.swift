import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces with LSUIElement: no Dock icon however the app is launched.
        NSApp.setActivationPolicy(.accessory)
        let environment = AppEnvironment()
        self.environment = environment
        environment.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.shutdown()
    }

    /// Opening the app again (from Finder or Spotlight) shows the Library.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment?.customize.show(.library)
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

if MainActor.assumeIsolated({ DiagnosticRender.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ SelfTest.runIfRequested() }) { exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
