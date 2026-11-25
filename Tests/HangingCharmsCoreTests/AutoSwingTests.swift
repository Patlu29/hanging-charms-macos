import CoreGraphics
import Foundation
import Testing
@testable import HangingCharmsCore

@Suite struct AutoSwingTests {
    private func rope(_ style: RopeStyle = .thread, charms: [CharmMetrics] = [.default]) -> RopeSimulation {
        RopeSimulation(configuration: RopeConfiguration.make(unit: 260, style: style), anchor: CGPoint(x: 400, y: 0),
                       charms: charms, startAngle: 0)
    }

    /// The widest the charm swings either side over `seconds`, in radians.
    private func widest(_ rope: RopeSimulation, seconds: Double) -> (amplitude: Double, stretch: Double) {
        var amplitude = 0.0, stretch = 0.0
        for _ in 0..<Int(seconds * 60) {
            rope.step(deltaTime: 1 / 60)
            let reach = rope.charmRing(slot: rope.layout.slots.count - 1) - rope.anchor
            amplitude = max(amplitude, abs(atan2(reach.x, reach.y)))
            stretch = max(stretch, rope.maximumStretch)
        }
        return (amplitude, stretch)
    }

    @Test func offByDefault() {
        #expect(AppSettings().autoSwing == .off)
        #expect(rope().autoSwing == 0)
    }

    @Test func settingRoundTripsAndFallsBack() throws {
        var settings = AppSettings()
        settings.autoSwing = .large
        #expect(AppSettings.decode(settings.encoded()) == settings)
        let odd = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"autoSwing":"wild"}"#.utf8))
        #expect(odd.autoSwing == .off)
    }

    @Test func amplitudeFromEnergyIsExactAtTheTurningPointAndAtTheBottom() {
        #expect(abs(Pendulum.amplitude(angle: 0.4, angularSpeed: 0, length: 260, gravity: 2000) - 0.4) < 1e-9)
        // At the bottom, all energy is kinetic: 1 - cos A = L w^2 / 2g.
        let w = 1.2
        let expected = acos(1 - 260 * w * w / 4000)
        #expect(abs(Pendulum.amplitude(angle: 0, angularSpeed: w, length: 260, gravity: 2000) - expected) < 1e-9)
    }

    @Test(arguments: [AutoSwing.small, .medium, .large])
    func buildsToItsSizeAndHoldsIt(swing: AutoSwing) {
        let rope = rope()
        rope.autoSwing = swing.amplitude
        _ = widest(rope, seconds: 20)
        let held = widest(rope, seconds: 10)
        #expect(abs(held.amplitude - swing.amplitude) < swing.amplitude * 0.25,
                "held \(held.amplitude) for target \(swing.amplitude)")
        #expect(held.stretch <= RopeStyle.thread.physics.maxStretchRatio + 0.001)
        #expect(!rope.isSleeping)
    }

    @Test func largerSwingsWider() {
        let small = rope(), large = rope()
        small.autoSwing = AutoSwing.small.amplitude
        large.autoSwing = AutoSwing.large.amplitude
        #expect(widest(large, seconds: 25).amplitude > widest(small, seconds: 25).amplitude * 2)
    }

    @Test func aBigThrowSettlesBackToTheSwing() {
        let rope = rope(.goldChain)
        rope.autoSwing = AutoSwing.small.amplitude
        rope.applyImpulse(CGPoint(x: 1500, y: 0), at: rope.points.count - 1)
        _ = widest(rope, seconds: 40)
        let held = widest(rope, seconds: 10)
        #expect(abs(held.amplitude - AutoSwing.small.amplitude) < AutoSwing.small.amplitude * 0.3,
                "held \(held.amplitude)")
    }

    @Test func worksWithAStackOfCharmsOnEveryStyle() {
        for style in RopeStyle.allCases {
            let rope = rope(style, charms: [.default, .default, .default])
            rope.autoSwing = AutoSwing.medium.amplitude
            let result = widest(rope, seconds: 15)
            #expect(result.amplitude > 0.1, "\(style) barely swung")
            #expect(result.stretch <= style.physics.maxStretchRatio + 0.002, "\(style) stretched \(result.stretch)")
        }
    }

    @Test func holdingTheCharmPausesTheDrive() {
        let rope = rope()
        rope.autoSwing = AutoSwing.medium.amplitude
        _ = widest(rope, seconds: 5)
        let centre = rope.charmCentre(slot: 0)
        #expect(rope.beginDrag(at: centre))
        for _ in 0..<60 {
            rope.updateDrag(to: centre, velocity: .zero)
            rope.step(deltaTime: 1 / 60)
        }
        #expect(rope.swingAmplitude == 0)
        #expect(rope.charmCentre(slot: 0).distance(to: centre) < 3, "held charm is \(rope.charmCentre(slot: 0).distance(to: centre)) pt off, dragging \(rope.isDragging)")
    }

    @Test func turningItOffLetsTheRopeSleep() {
        let rope = rope(.leather)
        rope.autoSwing = AutoSwing.large.amplitude
        _ = widest(rope, seconds: 10)
        rope.autoSwing = 0
        for _ in 0..<(60 * 180) where !rope.isSleeping { rope.step(deltaTime: 1 / 60) }
        #expect(rope.isSleeping)
    }
}

@Suite struct AutoSwingDampingTests {
    @Test func heavyQuickSettlingRopesStillReachTheirSize() {
        let configuration = RopeConfiguration.make(unit: 260, style: .leather, settleSpeed: 3)
        let rope = RopeSimulation(configuration: configuration, anchor: .zero, startAngle: 0)
        rope.autoSwing = AutoSwing.medium.amplitude
        for _ in 0..<(60 * 20) { rope.step(deltaTime: 1 / 60) }
        var widest = 0.0
        for _ in 0..<(60 * 10) {
            rope.step(deltaTime: 1 / 60)
            let reach = rope.charmRing(slot: 0) - rope.anchor
            widest = max(widest, abs(atan2(reach.x, reach.y)))
        }
        #expect(abs(widest - AutoSwing.medium.amplitude) < AutoSwing.medium.amplitude * 0.25, "reached \(widest)")
    }
}
