import CoreGraphics
import Foundation
import Testing
@testable import HangingCharmsCore

@Suite struct HangingTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 945)

    @Test func defaultsHangFromTheMenuBarInStillAir() {
        let settings = AppSettings()
        #expect(settings.hangPoint == .menuBar)
        #expect(settings.breeze == .still)
    }

    @Test func hangingSettingsRoundTripAndClamp() throws {
        var settings = AppSettings()
        settings.hangPoint = .anywhere
        settings.pinX = 0.3
        settings.pinY = 0.6
        settings.breeze = .windy
        #expect(AppSettings.decode(settings.encoded()) == settings)
        let odd = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"hangPoint":"ceiling","pinX":4,"pinY":-1,"breeze":"hurricane"}"#.utf8))
        #expect(odd.hangPoint == .menuBar && odd.breeze == .still)
        #expect(odd.pinX == 1 && odd.pinY == 0)
    }

    @Test func notchAnchorSitsUnderTheCameraHousing() {
        // A 14-inch MacBook Pro: notch between x 662 and 850, 37 pt tall.
        let left = CGRect(x: 0, y: 945, width: 662, height: 37)
        let right = CGRect(x: 850, y: 945, width: 662, height: 37)
        let anchor = OverlayPlacement.notchAnchor(screenFrame: screen, visibleFrame: visible, leftArea: left, rightArea: right)
        #expect(anchor == CGPoint(x: 756, y: 37))
    }

    @Test func noNotchFallsBackToTheMiddleOfTheMenuBar() {
        let anchor = OverlayPlacement.notchAnchor(screenFrame: screen, visibleFrame: visible, leftArea: nil, rightArea: nil)
        #expect(anchor == CGPoint(x: 756, y: 37))
        let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let externalVisible = CGRect(x: 1512, y: 0, width: 2560, height: 1415)
        #expect(OverlayPlacement.notchAnchor(screenFrame: external, visibleFrame: externalVisible, leftArea: nil, rightArea: nil) == CGPoint(x: 1280, y: 25))
    }

    @Test func windowAnchorFollowsTheWindowsTopEdge() {
        // A window 300 pt from the left and 200 pt from the top of the primary display.
        let window = CGRect(x: 300, y: 200, width: 800, height: 500)
        let anchor = OverlayPlacement.windowAnchor(window: window, screenFrame: screen, visibleFrame: visible,
                                                   primaryHeight: 982, horizontal: 0.5)
        #expect(anchor == CGPoint(x: 700, y: 200))
        let moved = OverlayPlacement.windowAnchor(window: window.offsetBy(dx: 100, dy: 50), screenFrame: screen,
                                                  visibleFrame: visible, primaryHeight: 982, horizontal: 0.5)
        #expect(moved == CGPoint(x: 800, y: 250))
    }

    @Test func windowAnchorStaysOnScreenAndBelowTheMenuBar() {
        let offTop = CGRect(x: -400, y: -100, width: 300, height: 300)
        let anchor = OverlayPlacement.windowAnchor(window: offTop, screenFrame: screen, visibleFrame: visible,
                                                   primaryHeight: 982, horizontal: 0)
        #expect(anchor.x >= 8)
        #expect(anchor.y == 37)
    }

    @Test func windowAnchorOnASecondDisplay() {
        // A display to the right of the primary, top-aligned.
        let second = CGRect(x: 1512, y: -458, width: 2560, height: 1440)
        let window = CGRect(x: 2000, y: 300, width: 600, height: 400)
        let anchor = OverlayPlacement.windowAnchor(window: window, screenFrame: second, visibleFrame: second,
                                                   primaryHeight: 982, horizontal: 0.5)
        #expect(anchor == CGPoint(x: 2000 + 300 - 1512, y: 300))
    }

    @Test func pinRoundTripsThroughFractions() {
        let point = CGPoint(x: 400, y: 300)
        let pin = OverlayPlacement.pin(for: point, screenFrame: screen)
        let back = OverlayPlacement.pinnedAnchor(pin: pin, screenFrame: screen)
        #expect(back.distance(to: point) < 0.001)
        // Never pinned below the bottom tenth, so the charm stays on screen.
        #expect(OverlayPlacement.pin(for: CGPoint(x: 99999, y: 99999), screenFrame: screen) == CGPoint(x: 1, y: 0.9))
    }

    @Test func breezeMovesAStillCharmAndKeepsItAwake() {
        let rope = RopeSimulation(configuration: RopeConfiguration.make(unit: 260, style: .thread), anchor: CGPoint(x: 400, y: 0), startAngle: 0)
        for _ in 0..<600 { rope.step(deltaTime: 1 / 60) }
        #expect(rope.isSleeping)
        rope.breeze = Breeze.gentle.strength
        #expect(!rope.isSleeping)
        var furthest = 0.0
        var worst = 0.0
        for _ in 0..<(60 * 20) {
            rope.step(deltaTime: 1 / 60)
            furthest = max(furthest, abs(rope.charmRing(slot: 0).x - 400))
            worst = max(worst, rope.maximumStretch)
        }
        #expect(furthest > 3)
        #expect(!rope.isSleeping)
        #expect(worst <= RopeStyle.thread.physics.maxStretchRatio + 0.001)
    }

    @Test func windyMovesMoreThanGentle() {
        func sway(_ breeze: Breeze) -> Double {
            let rope = RopeSimulation(configuration: RopeConfiguration.make(unit: 260, style: .thread), anchor: .zero, startAngle: 0)
            rope.breeze = breeze.strength
            var furthest = 0.0
            for _ in 0..<(60 * 20) {
                rope.step(deltaTime: 1 / 60)
                furthest = max(furthest, abs(rope.charmRing(slot: 0).x))
            }
            return furthest
        }
        #expect(sway(.windy) > sway(.gentle) * 1.5)
    }

    @Test func stillAirLetsTheRopeSleepAgain() {
        let rope = RopeSimulation(configuration: RopeConfiguration.make(unit: 260, style: .leather), anchor: .zero, startAngle: 0)
        rope.breeze = Breeze.windy.strength
        for _ in 0..<120 { rope.step(deltaTime: 1 / 60) }
        rope.breeze = 0
        for _ in 0..<(60 * 120) where !rope.isSleeping { rope.step(deltaTime: 1 / 60) }
        #expect(rope.isSleeping)
    }

    @Test func gustsStayBounded() {
        for step in 0..<10_000 {
            #expect(abs(Gust.value(at: Double(step) * 0.05)) <= 1.0001)
        }
    }
}
