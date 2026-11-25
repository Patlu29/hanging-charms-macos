import CoreGraphics
import Foundation
import Testing
@testable import HangingCharmsCore

@Suite struct CharmStackTests {
    let configuration = RopeConfiguration.make(unit: 260, style: .thread)

    @Test func singleCharmHangsAtTheEndOfTheRope() {
        let layout = CharmStackLayout.resolve(metrics: [.default], configuration: configuration)
        #expect(layout.slots.count == 1)
        #expect(layout.slots[0].node == configuration.segmentCount)
        #expect(layout.pointCount == configuration.pointCount)
    }

    @Test func stackingAddsRopeBelowAndKeepsTheTopCharmInPlace() {
        let layout = CharmStackLayout.resolve(metrics: [.default, .default, .default], configuration: configuration)
        #expect(layout.slots.count == 3)
        #expect(layout.slots[0].node == configuration.segmentCount)
        #expect(layout.slots[1].node > layout.slots[0].node)
        #expect(layout.slots[2].node > layout.slots[1].node)
        let spacing = Double(layout.slots[1].node - layout.slots[0].node) * configuration.segmentLength
        #expect(spacing >= 2 * layout.slots[0].radius)
    }

    @Test func neverMoreThanThreeCharms() {
        let layout = CharmStackLayout.resolve(metrics: Array(repeating: .default, count: 6), configuration: configuration)
        #expect(layout.slots.count == CharmStackLayout.maximumCharms)
    }

    @Test func styleMassScaleWeighsCharms() {
        let heavy = CharmStackLayout.resolve(metrics: [.default], configuration: configuration, massScale: 1.4)
        #expect(abs(heavy.slots[0].mass - CharmMetrics.default.mass * 1.4) < 1e-9)
    }

    @Test func charmSizeScalesRadius() {
        let small = CharmStackLayout.resolve(metrics: [.default], configuration: configuration, charmSize: 0.5)
        let large = CharmStackLayout.resolve(metrics: [.default], configuration: configuration, charmSize: 1.5)
        #expect(abs(large.slots[0].radius / small.slots[0].radius - 3) < 1e-9)
    }

    @Test func stackedCharmsDoNotPassThroughEachOther() {
        let rope = RopeSimulation(
            configuration: configuration, anchor: CGPoint(x: 400, y: 0),
            charms: [.default, .default, .default], startAngle: 1.2
        )
        // Throw the bottom charm up past the others.
        let bottom = rope.layout.slots.count - 1
        #expect(rope.beginDrag(at: rope.charmCentre(slot: bottom)))
        for frame in 0..<40 {
            rope.updateDrag(to: CGPoint(x: 400 + Double(frame) * 4, y: 40), velocity: CGPoint(x: 0, y: -2400))
            rope.step(deltaTime: 1 / 60)
        }
        rope.endDrag()
        for _ in 0..<120 { rope.step(deltaTime: 1 / 60) }
        for first in 0..<(rope.layout.slots.count - 1) {
            for second in (first + 1)..<rope.layout.slots.count {
                let a = rope.charmRing(slot: first), b = rope.charmRing(slot: second)
                #expect(a.distance(to: b) >= 2 * rope.layout.slots[first].radius - 1)
            }
        }
    }

    @Test func reconfigureToMoreCharmsRebuilds() {
        let rope = RopeSimulation(configuration: configuration, anchor: .zero, charms: [.default])
        rope.reconfigure(configuration: configuration, charms: [.default, .default], charmSize: 1, massScale: 1)
        #expect(rope.layout.slots.count == 2)
        #expect(rope.points.count == rope.layout.pointCount)
    }
}

@Suite struct RopeStyleTests {
    @Test func threadIsTheDefaultSolver() {
        let thread = RopeStyle.thread.physics
        let defaults = RopeConfiguration.default
        #expect(thread.damping == defaults.damping)
        #expect(thread.maxStretchRatio == defaults.maxStretchRatio)
        #expect(thread.constraintIterations == defaults.constraintIterations)
    }

    @Test func everyStyleIsDistinct() {
        let profiles = RopeStyle.allCases.map { "\($0.physics)" }
        #expect(Set(profiles).count == RopeStyle.allCases.count)
    }

    @Test func goldChainIsTheHeaviest() {
        let heaviest = RopeStyle.allCases.max { $0.physics.charmMassScale < $1.physics.charmMassScale }
        #expect(heaviest == .goldChain)
    }

    @Test func afternoonIsIdentity() {
        let base = RopeConfiguration.default.applying(.thread, at: .afternoon)
        #expect(base.damping == RopeConfiguration.default.damping)
        #expect(base.initialAngle == RopeConfiguration.default.initialAngle)
    }

    @Test func applyingIsNotCumulative() {
        let once = RopeConfiguration.default.applying(.neon, at: .night)
        let twice = once.applying(.leather, at: .morning).applying(.neon, at: .night)
        #expect(once == twice)
    }

    @Test func nightLosesEnergyFaster() {
        let night = RopeConfiguration.default.applying(.thread, at: .night)
        let morning = RopeConfiguration.default.applying(.thread, at: .morning)
        #expect(night.damping < morning.damping)
    }

    @Test(arguments: [(4, RopeTimeProfile.night), (5, .morning), (11, .morning), (12, .afternoon), (17, .afternoon), (18, .night), (23, .night)])
    func timeOfDayBoundaries(hour: Int, expected: RopeTimeProfile) {
        #expect(RopeTimeProfile.forHour(hour) == expected)
    }
}
