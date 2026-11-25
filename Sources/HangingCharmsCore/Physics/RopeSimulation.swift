import CoreGraphics
import Foundation

/// A hanging rope simulated with Verlet integration and position-based constraints.
///
/// Step order, per fixed slice:
/// 1. **Pin the anchor**, so a moved anchor drags the rope this step.
/// 2. **Integrate**: each free node moves by its damped displacement plus gravity.
/// 3. **Drive the held node** toward the cursor at a bounded speed.
/// 4. **Relax constraints**: Gauss-Seidel passes pull links to rest length and push
///    stacked charms apart, until converged or out of budget.
/// 5. **Clamp stretch**: a one-sided pass guarantees no link exceeds its ceiling.
///
/// Time advances in fixed slices, so the rope behaves identically at 60 Hz and 120 Hz;
/// the display only decides how often ``step(deltaTime:)`` is called.
///
/// The design follows the rope solver documented in Hangly-Windows
/// (`reference/swift/Physics`, MIT); this is an independent implementation.
public final class RopeSimulation {
    public private(set) var points: [RopePoint] = []
    public private(set) var anchor: CGPoint
    public private(set) var configuration: RopeConfiguration
    public private(set) var charms: [CharmMetrics]
    public private(set) var layout: CharmStackLayout
    public private(set) var charmSize: Double
    public private(set) var massScale: Double

    public private(set) var isSleeping = false

    /// Peak sideways push of the breeze, as a fraction of gravity. Zero is still air.
    /// While there is a breeze the rope never sleeps.
    public var breeze: Double = 0 {
        didSet { if breeze > 0 { wake() } }
    }
    /// The swing size to hold, in radians either side of straight down. Zero is off.
    /// While it is on the rope never sleeps.
    public var autoSwing: Double = 0 {
        didSet { if autoSwing > 0 { wake() } }
    }

    /// The swing's current size, as the auto swing measures it. For tests and debugging.
    public private(set) var swingAmplitude: Double = 0

    /// Simulated time, which drives the gusts.
    private var clock: Double = 0
    public private(set) var lastStepCount = 0

    /// Impacts since the last ``drainImpacts()``, each an intensity in 0...1.
    public private(set) var pendingImpacts: [Double] = []

    private var stillFrames = 0
    private var accumulator: TimeInterval = 0
    private var dragIndex: Int?
    private var dragTarget: CGPoint = .zero
    private var dragVelocity: CGPoint = .zero
    /// Where on the charm it was grabbed, in the charm's own frame: along its hanging
    /// direction and across it. Kept in that frame, not the screen's, so the spot under
    /// the pointer stays under the pointer as the charm turns with the rope.
    private var grabAlong = 0.0
    private var grabAcross = 0.0
    private var dragSlot: Int?
    /// The pointer, as last reported. The target is re-derived from it every step,
    /// because the charm keeps turning between mouse events.
    private var dragCursor: CGPoint = .zero
    private var contacts: Set<Int> = []
    private var brushContacts: Set<Int> = []

    public init(
        configuration: RopeConfiguration = .default,
        anchor: CGPoint = .zero,
        charms: [CharmMetrics] = [.default],
        charmSize: Double = 1,
        massScale: Double = 1,
        startAngle: Double? = nil
    ) {
        self.configuration = configuration
        self.anchor = anchor
        self.charms = charms.isEmpty ? [.default] : Array(charms.prefix(CharmStackLayout.maximumCharms))
        self.charmSize = charmSize
        self.massScale = massScale
        self.layout = CharmStackLayout.resolve(
            metrics: self.charms, configuration: configuration, charmSize: charmSize, massScale: massScale
        )
        reset(angle: startAngle ?? configuration.initialAngle)
    }

    // MARK: - Lifecycle

    /// Rebuilds the rope straight at `angle` from vertical, with no motion.
    public func reset(angle: Double) {
        let direction = CGPoint(x: 0, y: 1).rotated(by: angle)
        points = (0..<layout.pointCount).map { index in
            RopePoint(
                position: anchor + direction * (Double(index) * configuration.segmentLength),
                inverseMass: index == 0 ? 0 : 1
            )
        }
        applyMasses()
        accumulator = 0
        dragIndex = nil
        dragVelocity = .zero
        contacts = []
        wake()
    }

    /// Changes the rope without discarding its motion when the node count allows.
    public func reconfigure(
        configuration: RopeConfiguration,
        charms: [CharmMetrics],
        charmSize: Double,
        massScale: Double
    ) {
        self.configuration = configuration
        self.charms = charms.isEmpty ? [.default] : Array(charms.prefix(CharmStackLayout.maximumCharms))
        self.charmSize = charmSize
        self.massScale = massScale
        let newLayout = CharmStackLayout.resolve(
            metrics: self.charms, configuration: configuration, charmSize: charmSize, massScale: massScale
        )
        let rebuild = newLayout.pointCount != layout.pointCount
        layout = newLayout
        if rebuild {
            // Keep the current hang direction so the change reads as a swing, not a snap.
            let current = points.count > 1 ? (points[points.count - 1].position - anchor) : CGPoint(x: 0, y: 1)
            let angle = atan2(-current.x, current.y)
            reset(angle: angle.isFinite ? angle : 0)
        } else {
            applyMasses()
            dragIndex = nil
            wake()
        }
    }

    /// Moves the pinned end. The rope follows physically.
    public func setAnchor(_ point: CGPoint) {
        guard point != anchor else { return }
        anchor = point
        wake()
    }

    public func wake() {
        isSleeping = false
        stillFrames = 0
    }

    // MARK: - Stepping

    public func step(deltaTime: TimeInterval) {
        guard deltaTime > 0, !isSleeping else {
            lastStepCount = 0
            return
        }
        accumulator = min(accumulator + deltaTime, configuration.maxFrameDuration)
        let timeStep = configuration.fixedTimeStep
        var taken = 0
        while accumulator >= timeStep {
            advance(timeStep: timeStep)
            accumulator -= timeStep
            taken += 1
        }
        lastStepCount = taken
        updateSleepState()
    }

    private func advance(timeStep: Double) {
        enforceAnchor()
        integrate(timeStep: timeStep)
        driveDraggedPoint(timeStep: timeStep)

        var passes = 0
        var residual = Double.infinity
        while passes < configuration.constraintIterations, residual >= configuration.convergenceTolerance {
            residual = max(solveDistanceConstraints(), separateCharms())
            passes += 1
        }
        enforceMaximumStretch()
        detectContacts(timeStep: timeStep)
    }

    private func enforceAnchor() {
        guard !points.isEmpty else { return }
        points[0].position = anchor
        points[0].previousPosition = anchor
    }

    private func integrate(timeStep: Double) {
        clock += timeStep
        let gust = breeze > 0 ? configuration.gravity * breeze * Gust.value(at: clock) : 0
        let gravityStep = CGPoint(x: gust * timeStep * timeStep, y: configuration.gravity * timeStep * timeStep)
        let damping = configuration.damping
        let limit = configuration.maximumSpeed * timeStep
        let drive = autoSwingDrive(timeStep: timeStep)
        let last = Double(max(1, points.count - 1))
        for index in points.indices where index != dragIndex && points[index].inverseMass > 0 {
            var point = points[index]
            let carried = (point.displacement * damping).limited(to: limit)
            point.previousPosition = point.position
            // The drive scales with distance down the rope, so the whole cord swings
            // together like a pendulum rather than being tugged at the end.
            point.position += carried + gravityStep + drive * (Double(index) / last)
            points[index] = point
        }
    }

    /// The push that keeps an auto swing at its size, as a displacement for one step.
    ///
    /// It reads the swing's amplitude from its energy, then pushes along the direction of
    /// travel when the swing is too small and against it when too big, so a throw or a
    /// nudge settles back into the rhythm. It is gentle by design: the rope's own
    /// damping is only a little smaller than the push, so the swing builds over a few
    /// periods rather than snapping to size.
    private func autoSwingDrive(timeStep: Double) -> CGPoint {
        guard autoSwing > 0, dragIndex == nil, let end = points.indices.last, end > 0 else {
            swingAmplitude = 0
            return .zero
        }
        let reach = points[end].position - anchor
        let length = reach.magnitude
        guard length > 1 else { return .zero }
        let angle = atan2(reach.x, reach.y)
        let tangent = CGPoint(x: reach.y / length, y: -reach.x / length)
        let angularSpeed = points[end].displacement.dot(tangent) / length / timeStep
        swingAmplitude = Pendulum.amplitude(angle: angle, angularSpeed: angularSpeed, length: length,
                                            gravity: configuration.gravity)
        let error = autoSwing - swingAmplitude
        // At rest there is no direction of travel yet: start it towards the right.
        let direction: Double = abs(angularSpeed) < 0.02 ? 1 : (angularSpeed > 0 ? 1 : -1)
        let gain = 0.9
        let acceleration = configuration.gravity * gain * min(max(error, -0.3), 0.3) * direction
        // While the swing is too small, also hand back what damping takes from it this
        // step, so heavy, quick-settling ropes reach the same size as light ones.
        let swingStep = points[end].displacement.dot(tangent)
        let restore = error > 0 ? swingStep * (1 - configuration.damping) : 0
        return tangent * (acceleration * timeStep * timeStep + restore)
    }

    private func driveDraggedPoint(timeStep: Double) {
        guard let dragIndex else { return }
        if dragSlot != nil { dragTarget = reachableTarget(for: dragCursor - grabOffsetNow()) }
        let current = points[dragIndex].position
        let travel = configuration.maximumSpeed * timeStep
        points[dragIndex].position = current + (dragTarget - current).limited(to: travel)
        points[dragIndex].setVelocity(dragVelocity, timeStep: timeStep)
    }

    private func updateSleepState() {
        guard dragIndex == nil, breeze <= 0, autoSwing <= 0 else {
            stillFrames = 0
            return
        }
        let limit = configuration.restSpeed * configuration.fixedTimeStep
        if points.contains(where: { $0.displacement.magnitude > limit }) {
            stillFrames = 0
            return
        }
        stillFrames += 1
        if stillFrames >= configuration.framesBeforeSleep {
            isSleeping = true
        }
    }

    private func applyMasses() {
        for index in points.indices {
            points[index].inverseMass = index == 0 ? 0 : 1
        }
        for slot in layout.slots where points.indices.contains(slot.node) {
            points[slot.node].inverseMass = 1 / slot.mass
        }
    }

    // MARK: - Constraints

    private func effectiveInverseMass(at index: Int) -> Double {
        index == dragIndex ? 0 : points[index].inverseMass
    }

    @discardableResult
    private func solveDistanceConstraints() -> Double {
        let rest = configuration.segmentLength
        let stiffness = configuration.linkStiffness
        var largest = 0.0
        for index in 0..<(points.count - 1) {
            let a = effectiveInverseMass(at: index)
            let b = effectiveInverseMass(at: index + 1)
            let total = a + b
            guard total > 0 else { continue }
            let delta = points[index + 1].position - points[index].position
            let distance = delta.magnitude
            guard distance > .ulpOfOne else { continue }
            let correction = delta * (stiffness * (distance - rest) / distance / total)
            points[index].position += correction * a
            points[index + 1].position -= correction * b
            largest = max(largest, (correction * max(a, b)).magnitude)
        }
        return largest
    }

    /// Keeps stacked charms from passing through one another, every pair, one-sided.
    @discardableResult
    private func separateCharms() -> Double {
        let slots = layout.slots
        guard slots.count > 1 else { return 0 }
        let gap = CharmStackLayout.gap(for: configuration) * 0.5
        var largest = 0.0
        for first in 0..<(slots.count - 1) {
            for second in (first + 1)..<slots.count {
                let upper = slots[first].node, lower = slots[second].node
                let minimum = (2 * slots[first].radius) + gap
                let a = effectiveInverseMass(at: upper), b = effectiveInverseMass(at: lower)
                let total = a + b
                guard total > 0 else { continue }
                let delta = points[lower].position - points[upper].position
                let distance = delta.magnitude
                guard distance < minimum else { continue }
                let direction = distance > .ulpOfOne ? delta / distance : CGPoint(x: 0, y: 1)
                let correction = direction * ((distance - minimum) / total)
                points[upper].position += correction * a
                points[lower].position -= correction * b
                largest = max(largest, (correction * max(a, b)).magnitude)
            }
        }
        return largest
    }

    private func enforceMaximumStretch() {
        let limit = configuration.segmentLength * configuration.maxStretchRatio
        let links = points.count - 1
        for pass in 0..<max(1, configuration.stretchPasses) {
            var corrected = false
            // Alternating the sweep direction (symmetric Gauss-Seidel) lets a correction
            // travel the whole chain in one pass either way. A one-way sweep on a taut
            // chain pinned at both ends (anchor and a held charm) converges far slower.
            for step in 0..<links {
                let index = pass.isMultiple(of: 2) ? step : links - 1 - step
                let a = effectiveInverseMass(at: index)
                let b = effectiveInverseMass(at: index + 1)
                let total = a + b
                guard total > 0 else { continue }
                let delta = points[index + 1].position - points[index].position
                let distance = delta.magnitude
                guard distance > limit else { continue }
                let correction = delta * ((distance - limit) / distance / total)
                points[index].position += correction * a
                points[index + 1].position -= correction * b
                corrected = true
            }
            if !corrected { return }
        }
        projectInextensible(limit: limit)
    }

    /// The guarantee behind the ceiling, for the rare frame relaxation cannot settle.
    ///
    /// A nearly taut chain held at both ends (the anchor and a held charm) with a bow
    /// in it converges very slowly under Gauss-Seidel: each correction is almost along
    /// the chord, and straightening the bow needs sideways movement. FABRIK passes
    /// between the two pinned ends converge in a handful of iterations whenever the
    /// held node is in reach, which ``reachableTarget(for:)`` makes sure of. Below the
    /// held node (or on the whole rope when nothing is held) a single follow-the-leader
    /// pass from the top is exact.
    private func projectInextensible(limit: Double) {
        func pull(_ moving: Int, toward fixed: Int) {
            let delta = points[moving].position - points[fixed].position
            let distance = delta.magnitude
            guard distance > limit else { return }
            points[moving].position = points[fixed].position + delta * (limit / distance)
        }

        if let held = dragIndex, held > 0 {
            let heldPosition = points[held].position
            for _ in 0..<16 {
                for index in 0..<held { pull(index + 1, toward: index) }
                points[held].position = heldPosition
                for index in stride(from: held, to: 0, by: -1) { pull(index - 1, toward: index) }
                points[0].position = anchor
                let over = (0..<held).contains {
                    points[$0].position.distance(to: points[$0 + 1].position) > limit * 1.0001
                }
                if !over { break }
            }
        }
        // Final authority, from the anchor down. If the held charm is still further
        // than a bowed rope can reach this frame, it lags the cursor for that frame:
        // a taut cord holds it back rather than stretching, which is what a real one does.
        for index in 0..<(points.count - 1) { pull(index + 1, toward: index) }
    }

    /// Records a chime when two stacked charms meet with some speed.
    private func detectContacts(timeStep: Double) {
        let slots = layout.slots
        guard slots.count > 1 else { return }
        for index in 0..<(slots.count - 1) {
            let upper = slots[index], lower = slots[index + 1]
            let centreA = charmCentre(slot: index), centreB = charmCentre(slot: index + 1)
            let touching = centreA.distance(to: centreB) < (upper.radius + lower.radius) * 1.02
            if touching, !contacts.contains(index) {
                let relative = (points[lower.node].displacement - points[upper.node].displacement).magnitude / timeStep
                if relative > 90 {
                    pendingImpacts.append(min(1, relative / 1400))
                }
                contacts.insert(index)
            } else if !touching {
                contacts.remove(index)
            }
        }
    }

    // MARK: - Charm geometry

    /// The direction the charm in `slot` hangs: along the cord at its ring.
    public func charmDirection(slot: Int) -> CGPoint {
        guard layout.slots.indices.contains(slot) else { return CGPoint(x: 0, y: 1) }
        let node = layout.slots[slot].node
        // A held charm hangs along the pull towards the pointer, the same frame the drag
        // is solved in, so what is drawn under the pointer is the spot that was grabbed.
        if slot == dragSlot, node > 0 {
            let pull = dragCursor - points[node - 1].position
            if pull.magnitude > 1 { return pull.normalized }
        }
        let above = points[max(0, node - 1)].position
        let below = node + 1 < points.count ? points[node + 1].position : points[node].position
        let direction = node + 1 < points.count ? (below - above) : (points[node].position - above)
        return direction.normalized
    }

    /// Angle of the charm from hanging straight down, in radians (clockwise on screen).
    public func charmAngle(slot: Int) -> Double {
        let direction = charmDirection(slot: slot)
        return atan2(-direction.x, direction.y)
    }

    /// Where the ring of the charm in `slot` is.
    public func charmRing(slot: Int) -> CGPoint {
        guard layout.slots.indices.contains(slot) else { return anchor }
        return points[layout.slots[slot].node].position
    }

    public func charmCentre(slot: Int) -> CGPoint {
        guard layout.slots.indices.contains(slot) else { return anchor }
        return charmRing(slot: slot) + charmDirection(slot: slot) * layout.slots[slot].radius
    }

    // MARK: - Interaction

    public var isDragging: Bool { dragIndex != nil }

    /// The stacked charm (counted from the anchor) under `location`, nearest first.
    public func charmSlot(at location: CGPoint) -> Int? {
        var best: Int?
        var bestDistance = Double.infinity
        for slot in layout.slots.indices.reversed() {
            let distance = charmCentre(slot: slot).distance(to: location)
            guard distance <= layout.slots[slot].radius + RopeConfiguration.grabPadding,
                  distance < bestDistance else { continue }
            best = slot
            bestDistance = distance
        }
        return best
    }

    public func canGrab(at location: CGPoint) -> Bool { charmSlot(at: location) != nil }

    @discardableResult
    public func beginDrag(at location: CGPoint) -> Bool {
        guard let slot = charmSlot(at: location) else { return false }
        let node = layout.slots[slot].node
        dragIndex = node
        let offset = location - points[node].position
        let direction = charmDirection(slot: slot)
        let across = CGPoint(x: -direction.y, y: direction.x)
        grabAlong = offset.dot(direction)
        grabAcross = offset.dot(across)
        dragSlot = slot
        dragCursor = location
        dragTarget = points[node].position
        dragVelocity = .zero
        pendingImpacts.append(0.25)
        wake()
        return true
    }

    /// - Parameter velocity: Cursor velocity in points per second.
    public func updateDrag(to location: CGPoint, velocity: CGPoint) {
        guard dragIndex != nil else { return }
        dragCursor = location
        dragTarget = reachableTarget(for: location - grabOffsetNow())
        dragVelocity = velocity.limited(to: configuration.maximumSpeed)
        wake()
    }

    /// Pins the target to the circle the rope above the held node can reach, so
    /// pulling past the rope's length swings the charm rather than stretching it.
    public func reachableTarget(for location: CGPoint) -> CGPoint {
        let held = Double(dragIndex ?? (points.count - 1)) * configuration.segmentLength
        // The full length of the rope, not 98% of it: anything shorter made a charm hop
        // towards the anchor the moment it was picked up from where it hangs. The final
        // projection pass keeps every link inside the ceiling whatever the target.
        let give = configuration.linkStiffness < 1 ? configuration.maxStretchRatio : 1
        let reach = held * give
        let offset = location - anchor
        let distance = offset.magnitude
        guard distance > reach, distance > .ulpOfOne else { return location }
        return anchor + (offset / distance) * reach
    }

    /// The grab offset in screen terms for the way the charm hangs right now.
    ///
    /// The frame is taken from the rope node above the charm towards the pointer, not
    /// from the charm's own last link: that link is the one the drag moves, so measuring
    /// from it made the offset chase itself and the charm lag behind the pointer. Taken
    /// this way the held charm lines up with the cord pulling on it, which is where a
    /// real one hangs when held, and the grabbed spot sits under the pointer at once.
    private func grabOffsetNow() -> CGPoint {
        guard let dragSlot, let dragIndex, dragIndex > 0 else { return .zero }
        let pull = dragCursor - points[dragIndex - 1].position
        let direction = pull.magnitude > 1 ? pull.normalized : charmDirection(slot: dragSlot)
        let across = CGPoint(x: -direction.y, y: direction.x)
        return direction * grabAlong + across * grabAcross
    }

    public func endDrag() {
        dragSlot = nil
        dragIndex = nil
        dragVelocity = .zero
    }

    /// Gives a node a velocity, as if something hit it.
    public func applyImpulse(_ velocity: CGPoint, at index: Int) {
        guard points.indices.contains(index), points[index].inverseMass > 0 else { return }
        points[index].previousPosition = points[index].position - velocity * configuration.fixedTimeStep
        wake()
    }

    /// How fast the pointer must be moving to knock a charm, in points per second.
    /// Slower than this is someone reaching for the charm to pick it up, and pushing it
    /// away then is what makes a charm impossible to catch.
    public static let flickSpeed = 650.0

    /// A cursor passing through the rope or a charm nudges it, for the mouse-reactive rope.
    ///
    /// The nudge is added to the node's motion rather than replacing it, and a charm is
    /// knocked once per pass through it, not on every mouse event while the pointer is
    /// inside. Both matter: replacing the velocity on every event made a hovering pointer
    /// fight the swing, and repeating the push made the charm flee the pointer.
    /// - Returns: Whether anything was touched.
    @discardableResult
    public func brush(at location: CGPoint, velocity: CGPoint, strength: Double = 0.35) -> Bool {
        guard dragIndex == nil else {
            brushContacts = []
            return false
        }
        let speed = velocity.magnitude
        let dt = configuration.fixedTimeStep
        var touched = false
        var inside: Set<Int> = []
        var charmNodes: Set<Int> = []
        for slot in layout.slots.indices {
            charmNodes.insert(layout.slots[slot].node)
            guard charmCentre(slot: slot).distance(to: location) < layout.slots[slot].radius else { continue }
            inside.insert(slot)
            guard !brushContacts.contains(slot), speed > Self.flickSpeed else { continue }
            let node = layout.slots[slot].node
            points[node].previousPosition -= velocity.limited(to: 1800) * strength * dt
            touched = true
        }
        brushContacts = inside
        if speed > 120 {
            let nudge = velocity.limited(to: 1200) * (strength * 0.4) * dt
            for index in points.indices.dropFirst() where !charmNodes.contains(index)
                && points[index].position.distance(to: location) < 8 {
                points[index].previousPosition -= nudge
                touched = true
            }
        }
        if touched { wake() }
        return touched
    }

    public func drainImpacts() -> [Double] {
        defer { pendingImpacts.removeAll(keepingCapacity: true) }
        return pendingImpacts
    }

    // MARK: - Measurements

    /// Longest link as a multiple of rest length. Used by tests and the debug read-out.
    public var maximumStretch: Double {
        var longest = 0.0
        for index in 0..<(points.count - 1) {
            longest = max(longest, points[index].position.distance(to: points[index + 1].position))
        }
        return longest / configuration.segmentLength
    }

    /// Bounding box of the rope and every charm, in canvas points.
    public var bounds: CGRect {
        var rect = CGRect(origin: anchor, size: .zero)
        for point in points { rect = rect.union(CGRect(origin: point.position, size: .zero)) }
        for slot in layout.slots.indices {
            let r = layout.slots[slot].radius
            let c = charmCentre(slot: slot)
            rect = rect.union(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        return rect
    }
}
