import AppKit
import HangingCharmsCore

/// `HangingCharms --self-test` drives the real overlay panel with synthetic mouse events
/// and live settings changes, and exits non-zero if anything fails.
///
/// It uses a throwaway settings suite and charm folder, never the user's own, and moves a
/// simulated pointer rather than the real cursor. The panel is briefly visible on screen
/// while it runs, because the frame loop only ticks for a window that is on screen.
@MainActor
final class SelfTest {
    private var passed = 0
    private var failures: [String] = []
    private let store: SettingsStore
    private let library: CharmLibrary
    private let overlay: OverlayController
    private var eventNumber = 0

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--self-test") else { return false }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let test = SelfTest()
        test.run()
        exit(test.failures.isEmpty ? 0 : 1)
    }

    private init() {
        let suite = "HangingCharms.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        store = SettingsStore(defaults: defaults)
        library = CharmLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("hc-selftest-\(UUID().uuidString)"))
        // A still, quick-settling rope in the middle of the main display.
        store.update {
            $0.reduceMotion = true
            $0.hideInFullScreen = false
            $0.sounds = false
            $0.horizontalPosition = 0.5
            $0.ropeStyle = .leather
            $0.settleSpeed = 3
            $0.level = .aboveAll
        }
        overlay = OverlayController(store: store, library: library, audio: AudioService())
        overlay.followsRealPointer = false
    }

    // MARK: - Harness

    private func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            passed += 1
            print("PASS  \(name)")
        } else {
            let message = detail()
            failures.append(name)
            print("FAIL  \(name)\(message.isEmpty ? "" : ": \(message)")")
        }
    }

    /// Lets the display link run for `seconds` of real time.
    private func pump(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private var rope: RopeSimulation { overlay.testRope! }
    private var panel: OverlayPanel { overlay.testPanel! }

    private func charmCentre(_ slot: Int = 0) -> CGPoint { rope.charmCentre(slot: slot) }

    private func screen(_ canvas: CGPoint) -> CGPoint { overlay.screenPoint(fromCanvas: canvas)! }

    private func send(_ type: NSEvent.EventType, atCanvas point: CGPoint, clickCount: Int = 1) {
        eventNumber += 1
        let window = CGPoint(x: point.x, y: panel.frame.height - point.y)
        guard let event = NSEvent.mouseEvent(
            with: type, location: window, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, eventNumber: eventNumber, clickCount: clickCount, pressure: 1
        ) else { return }
        panel.sendEvent(event)
    }

    // MARK: - The run

    private func run() {
        print("Hanging Charms self-test")
        overlay.start()
        pump(0.5)

        check("panel is on screen", panel.isVisible)
        check("panel lets clicks through away from the charm", panel.ignoresMouseEvents)
        check("panel accepts mouse-moved events", panel.acceptsMouseMovedEvents)
        check("rope has one charm", rope.layout.slots.count == 1)
        check("grapple is drawn by default", overlay.testRenderer.isGrappleShown)
        check("default hook has no jump ring", store.settings.hookStyle == .knot)

        // Motion back on, now that the rope is hanging still.
        store.update { $0.reduceMotion = false; $0.mouseReactive = true }
        pump(0.3)

        hoverChecks()
        slowApproachCheck()
        grabAndThrowChecks()
        missedClickCheck()
        flickCheck()
        settingsChecks()
        visibilityAndSleepChecks()

        overlay.stop()
        print("\n\(passed) passed, \(failures.count) failed")
        if !failures.isEmpty { print("Failed: \(failures.joined(separator: "; "))") }
    }

    private func hoverChecks() {
        overlay.simulatePointer(atScreen: screen(charmCentre()))
        check("hovering a charm makes the panel take the mouse", !panel.ignoresMouseEvents)
        overlay.simulatePointer(atScreen: screen(CGPoint(x: charmCentre().x + 400, y: charmCentre().y)))
        check("moving off the charm gives the mouse back", panel.ignoresMouseEvents)
    }

    private func slowApproachCheck() {
        let start = charmCentre()
        for step in 0...20 {
            overlay.simulatePointer(atScreen: screen(CGPoint(x: start.x - 80 + Double(step) * 4, y: start.y)))
            pump(1.0 / 60)
        }
        pump(0.2)
        check("reaching slowly for the charm does not push it away", charmCentre().distance(to: start) < 3,
              String(format: "moved %.1f pt", charmCentre().distance(to: start)))
        check("the charm can be caught after a slow approach", rope.canGrab(at: CGPoint(x: start.x, y: start.y)))
    }

    private func grabAndThrowChecks() {
        let grab = charmCentre()
        overlay.simulatePointer(atScreen: screen(grab))
        check("pointer over the charm before the grab", !panel.ignoresMouseEvents)
        send(.leftMouseDown, atCanvas: grab)
        check("mouse down on the charm picks it up", rope.isDragging)

        var worstStretch = 0.0
        var target = grab
        // Up and across, staying inside the circle the rope can reach, so the charm
        // should track the pointer closely rather than lag on a taut rope.
        for _ in 0..<14 {
            target = CGPoint(x: target.x + 6, y: target.y - 8)
            send(.leftMouseDragged, atCanvas: target)
            pump(1.0 / 60)
            worstStretch = max(worstStretch, rope.maximumStretch)
        }
        pump(0.05)
        check("the held charm follows the pointer", charmCentre().distance(to: target) < 12,
              String(format: "%.1f pt behind", charmCentre().distance(to: target)))

        // Then out past the rope's reach: the rope goes taut and the charm stays on it.
        let far = CGPoint(x: target.x + 600, y: target.y)
        for step in 1...10 {
            send(.leftMouseDragged, atCanvas: CGPoint(x: target.x + Double(step) * 60, y: target.y))
            pump(1.0 / 60)
            worstStretch = max(worstStretch, rope.maximumStretch)
        }
        pump(0.1)
        let reach = Double(rope.layout.slots[0].node) * rope.configuration.segmentLength
        check("pulled past its reach, the charm stays on a taut rope",
              rope.charmRing(slot: 0).distance(to: rope.anchor) <= reach * rope.configuration.maxStretchRatio + 1)
        target = CGPoint(x: target.x + 360, y: target.y)
        _ = far

        // Swing it back fast, then let go.
        for step in 1...8 {
            send(.leftMouseDragged, atCanvas: CGPoint(x: target.x - Double(step) * 70, y: target.y))
            pump(1.0 / 120)
        }
        target = CGPoint(x: target.x - 560, y: target.y)
        send(.leftMouseUp, atCanvas: target)
        check("mouse up lets go", !rope.isDragging)
        let released = charmCentre()
        var furthest = 0.0
        for _ in 0..<20 {
            pump(1.0 / 60)
            furthest = max(furthest, charmCentre().distance(to: released))
            worstStretch = max(worstStretch, rope.maximumStretch)
        }
        check("the thrown charm keeps moving after release", furthest > 15, String(format: "moved %.1f pt", furthest))
        let ceiling = store.settings.ropeStyle.physics.maxStretchRatio + 0.002
        check("the rope never stretches past its ceiling", worstStretch <= ceiling,
              String(format: "%.4f > %.4f", worstStretch, ceiling))
    }

    private func missedClickCheck() {
        // A click that reaches the panel where there is no charm (it swung away between
        // the hover check and the click) must give the mouse back.
        panel.ignoresMouseEvents = false
        send(.leftMouseDown, atCanvas: CGPoint(x: 20, y: 20))
        check("a click away from any charm picks nothing up", !rope.isDragging)
        check("a click away from any charm hands the mouse back", panel.ignoresMouseEvents)
        send(.leftMouseUp, atCanvas: CGPoint(x: 20, y: 20))
    }

    private func flickCheck() {
        // Wait for the throw to calm down, then flick through the charm quickly.
        for _ in 0..<60 where !rope.isSleeping { pump(0.1) }
        let centre = charmCentre()
        overlay.simulatePointer(atScreen: screen(CGPoint(x: centre.x - 120, y: centre.y)))
        pump(0.02)
        overlay.simulatePointer(atScreen: screen(CGPoint(x: centre.x - 2, y: centre.y)))
        pump(0.15)
        check("a quick flick through the charm knocks it", charmCentre().distance(to: centre) > 3,
              String(format: "moved %.1f pt", charmCentre().distance(to: centre)))
        overlay.simulatePointer(atScreen: screen(CGPoint(x: centre.x + 600, y: centre.y + 300)))
    }

    private func settingsChecks() {
        store.update { $0.charmIDs = ["evil-eye", "clover", "heart"] }
        pump(0.1)
        check("three charms hang on the rope", rope.layout.slots.count == 3 && overlay.testRenderer.charmLayerCount == 3)

        let before = rope.layout.slots[2].radius
        store.update { $0.setScale(1.5, for: "heart") }
        pump(0.05)
        check("a charm's own size scales it", abs(rope.layout.slots[2].radius / before - 1.5) < 0.01)

        var allHooks = true
        for style in HookStyle.allCases {
            store.update { $0.hookStyle = style }
            pump(0.02)
            allHooks = allHooks && overlay.testRenderer.charmLayerCount == 3
        }
        check("every hook style applies live", allHooks)

        var grapples = true
        for style in GrappleStyle.allCases {
            store.update { $0.grappleStyle = style }
            pump(0.02)
            grapples = grapples && overlay.testRenderer.isGrappleShown == (style != .none)
        }
        check("every grapple applies live, and Nothing hides it", grapples)

        store.update { $0.beads = .many; $0.reduceMotion = false }
        rope.wake()
        pump(0.1)
        check("beads are drawn along the rope", overlay.testRenderer.beadsDrawn)
        store.update { $0.beads = .none }
        pump(0.05)
        check("beads can be taken off", !overlay.testRenderer.beadsDrawn)

        var styles = true
        for style in RopeStyle.allCases {
            store.update { $0.ropeStyle = style }
            pump(0.02)
            styles = styles && rope.configuration.maxStretchRatio == style.physics.maxStretchRatio
        }
        check("every rope style applies its own physics", styles)

        store.update {
            $0.ropeThickness = AppSettings.ropeThicknessRange.upperBound
            $0.linkSize = 2
            $0.ropePattern = .chain
            $0.customRopeColors = true
            $0.ropeGlow = true
        }
        pump(0.05)
        check("thread thickness, links, pattern and colours apply without rebuilding the rope", rope.layout.slots.count == 3)
        store.update { $0.charmIDs = ["evil-eye"]; $0.ropeStyle = .leather; $0.ropeThickness = 1 }
        pump(0.05)
    }

    private func visibilityAndSleepChecks() {
        store.update { $0.isVisible = false }
        pump(0.05)
        check("hiding the charm hides the panel", !panel.isVisible)
        store.update { $0.isVisible = true }
        pump(0.05)
        check("showing the charm brings the panel back", panel.isVisible)

        var waited = 0.0
        while !(rope.isSleeping && overlay.isFrameLoopPaused), waited < 40 {
            pump(0.25)
            waited += 0.25
        }
        check("a settled rope stops the frame loop", rope.isSleeping && overlay.isFrameLoopPaused,
              String(format: "still moving after %.0f s", waited))
    }
}
