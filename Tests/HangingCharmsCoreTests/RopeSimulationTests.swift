import CoreGraphics
import Foundation
import Testing
@testable import HangingCharmsCore

@Suite struct RopeSimulationTests {
    private func makeRope(
        style: RopeStyle = .thread,
        charms: [CharmMetrics] = [.default],
        elastic: Bool = false,
        angle: Double? = nil
    ) -> RopeSimulation {
        let configuration = RopeConfiguration.make(unit: 260, style: style, elastic: elastic)
        return RopeSimulation(configuration: configuration, anchor: CGPoint(x: 400, y: 0), charms: charms, startAngle: angle)
    }

    private func run(_ rope: RopeSimulation, seconds: Double, hz: Double = 60) {
        let frames = Int(seconds * hz)
        for _ in 0..<frames { rope.step(deltaTime: 1 / hz) }
    }

    @Test func buildsTwentySegmentsWithPinnedAnchor() {
        let rope = makeRope()
        #expect(rope.points.count == 21)
        #expect(rope.points[0].isPinned)
        #expect(rope.points.dropFirst().allSatisfy { !$0.isPinned })
    }

    @Test func charmNodeCarriesCharmMass() {
        let rope = makeRope(charms: [CharmMetrics(mass: 5)])
        #expect(abs(rope.points.last!.inverseMass - 0.2) < 1e-9)
    }

    @Test func anchorNeverMoves() {
        let rope = makeRope()
        run(rope, seconds: 2)
        #expect(rope.points[0].position == CGPoint(x: 400, y: 0))
    }

    @Test(arguments: RopeStyle.allCases)
    func neverStretchesPastCeilingWhileSwinging(style: RopeStyle) {
        let rope = makeRope(style: style, angle: 1.2)
        var worst = 0.0
        for _ in 0..<240 {
            rope.step(deltaTime: 1 / 60)
            worst = max(worst, rope.maximumStretch)
        }
        #expect(worst <= style.physics.maxStretchRatio + 0.001)
    }

    @Test func survivesAHardThrowWithinCeiling() {
        let rope = makeRope(style: .goldChain)
        let grab = rope.charmCentre(slot: 0)
        #expect(rope.beginDrag(at: grab))
        var worst = 0.0
        for frame in 0..<30 {
            let target = CGPoint(x: grab.x + Double(frame) * 60, y: grab.y - Double(frame) * 30)
            rope.updateDrag(to: target, velocity: CGPoint(x: 3600, y: -1800))
            rope.step(deltaTime: 1 / 60)
            worst = max(worst, rope.maximumStretch)
        }
        rope.endDrag()
        for _ in 0..<120 {
            rope.step(deltaTime: 1 / 60)
            worst = max(worst, rope.maximumStretch)
        }
        #expect(worst <= RopeStyle.goldChain.physics.maxStretchRatio + 0.001, "worst \(worst)")
    }

    @Test func gravityPullsTheCharmBelowTheAnchor() {
        let rope = makeRope(angle: 0.9)
        run(rope, seconds: 0.2)
        #expect(rope.charmRing(slot: 0).y > 0)
    }

    @Test func settlesAndSleeps() {
        let rope = makeRope(style: .leather, angle: 0.5)
        run(rope, seconds: 90)
        #expect(rope.isSleeping)
        // Settled straight below the anchor.
        #expect(abs(rope.charmRing(slot: 0).x - 400) < 2)
    }

    @Test func wakeAfterImpulse() {
        let rope = makeRope(style: .leather, angle: 0)
        run(rope, seconds: 5)
        #expect(rope.isSleeping)
        rope.applyImpulse(CGPoint(x: 500, y: 0), at: rope.points.count - 1)
        #expect(!rope.isSleeping)
    }

    @Test func refreshRateDoesNotChangeTheMotion() {
        let slow = makeRope(angle: 0.6)
        let fast = makeRope(angle: 0.6)
        run(slow, seconds: 1, hz: 60)
        run(fast, seconds: 1, hz: 120)
        #expect(slow.charmRing(slot: 0).distance(to: fast.charmRing(slot: 0)) < 0.5)
    }

    @Test func longFrameDoesNotTeleport() {
        let rope = makeRope(angle: 0.6)
        rope.step(deltaTime: 5)
        #expect(rope.lastStepCount <= Int((0.1 / (1.0 / 240)).rounded(.up)))
    }

    @Test func dragTracksTheCursorAndMomentumSurvivesRelease() {
        let rope = makeRope(angle: 0)
        let start = rope.charmCentre(slot: 0)
        #expect(rope.beginDrag(at: start))
        let target = CGPoint(x: start.x + 60, y: start.y - 10)
        for _ in 0..<20 {
            rope.updateDrag(to: target, velocity: CGPoint(x: 900, y: 0))
            rope.step(deltaTime: 1 / 60)
        }
        #expect(rope.charmCentre(slot: 0).distance(to: target) < 25)
        rope.endDrag()
        let before = rope.charmRing(slot: 0).x
        rope.step(deltaTime: 1 / 60)
        #expect(rope.charmRing(slot: 0).x > before)
    }

    @Test func grabMissesEmptySpace() {
        let rope = makeRope()
        #expect(!rope.beginDrag(at: CGPoint(x: -500, y: -500)))
        #expect(!rope.isDragging)
    }

    @Test func pullingPastTheRopeSwingsInsteadOfStretching() {
        let rope = makeRope(angle: 0)
        #expect(rope.beginDrag(at: rope.charmCentre(slot: 0)))
        for _ in 0..<60 {
            rope.updateDrag(to: CGPoint(x: 400, y: 5000), velocity: .zero)
            rope.step(deltaTime: 1 / 60)
        }
        #expect(rope.maximumStretch <= RopeStyle.thread.physics.maxStretchRatio + 0.001)
    }

    @Test func elasticRopeGivesButStaysUnderItsCeiling() {
        let rope = makeRope(elastic: true, angle: 1.3)
        var worst = 0.0
        for _ in 0..<240 {
            rope.step(deltaTime: 1 / 60)
            worst = max(worst, rope.maximumStretch)
        }
        #expect(worst > 1.03)
        #expect(worst <= RopeConfiguration.elasticCeiling + 0.001)
    }

    @Test func brushPushesTheCharm() {
        let rope = makeRope(style: .leather, angle: 0)
        run(rope, seconds: 5)
        let centre = rope.charmCentre(slot: 0)
        #expect(rope.brush(at: centre, velocity: CGPoint(x: 1200, y: 0)))
        rope.step(deltaTime: 1 / 60)
        #expect(rope.charmRing(slot: 0).x > centre.x)
    }

    @Test func remainsFiniteOverALongRun() {
        let rope = makeRope(style: .neon, angle: 1.5)
        run(rope, seconds: 120)
        #expect(rope.points.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
    }
}

@Suite struct BrushTests {
    private func settledRope() -> RopeSimulation {
        let rope = RopeSimulation(configuration: RopeConfiguration.make(unit: 260, style: .leather),
                                  anchor: CGPoint(x: 400, y: 0), startAngle: 0)
        for _ in 0..<300 { rope.step(deltaTime: 1 / 60) }
        return rope
    }

    @Test func reachingSlowlyForTheCharmDoesNotPushItAway() {
        let rope = settledRope()
        let centre = rope.charmCentre(slot: 0)
        // A pointer approaching at an ordinary reaching speed, ending on the charm.
        for step in 0..<20 {
            let point = CGPoint(x: centre.x - 60 + Double(step) * 3, y: centre.y)
            rope.brush(at: point, velocity: CGPoint(x: 300, y: 0))
            rope.step(deltaTime: 1 / 60)
        }
        #expect(rope.charmCentre(slot: 0).distance(to: centre) < 1)
        #expect(rope.canGrab(at: centre))
        #expect(rope.beginDrag(at: centre))
    }

    @Test func aFlickKnocksTheCharmOncePerPass() {
        let rope = settledRope()
        let centre = rope.charmCentre(slot: 0)
        let node = rope.layout.slots[0].node
        #expect(rope.brush(at: centre, velocity: CGPoint(x: 1500, y: 0)))
        let afterFirst = rope.points[node].displacement
        // Still inside the charm: no second knock.
        #expect(!rope.brush(at: CGPoint(x: centre.x + 2, y: centre.y), velocity: CGPoint(x: 1500, y: 0)))
        #expect(rope.points[node].displacement == afterFirst)
        // Out and back in: knocked again.
        rope.brush(at: CGPoint(x: centre.x + 500, y: centre.y), velocity: CGPoint(x: 1500, y: 0))
        #expect(rope.brush(at: centre, velocity: CGPoint(x: 1500, y: 0)))
    }

    @Test func brushingAddsToAnExistingSwingInsteadOfStoppingIt() {
        let rope = settledRope()
        let node = rope.layout.slots[0].node
        rope.applyImpulse(CGPoint(x: 800, y: 0), at: node)
        let before = rope.points[node].displacement.x
        rope.brush(at: rope.charmCentre(slot: 0), velocity: CGPoint(x: 1000, y: 0))
        #expect(rope.points[node].displacement.x > before)
    }

    @Test func noBrushWhileHolding() {
        let rope = settledRope()
        let centre = rope.charmCentre(slot: 0)
        #expect(rope.beginDrag(at: centre))
        #expect(!rope.brush(at: centre, velocity: CGPoint(x: 3000, y: 0)))
    }
}
