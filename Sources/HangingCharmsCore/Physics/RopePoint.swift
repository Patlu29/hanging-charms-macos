import CoreGraphics

/// One Verlet particle of the rope.
///
/// There is no velocity field: velocity is implied by the gap between where the node
/// is and where it was. That is why momentum survives a drag release for free.
public struct RopePoint: Equatable, Sendable {
    public var position: CGPoint
    public var previousPosition: CGPoint
    /// Reciprocal of mass. Zero pins the node (the anchor).
    public var inverseMass: Double

    public init(position: CGPoint, inverseMass: Double = 1) {
        self.position = position
        self.previousPosition = position
        self.inverseMass = inverseMass
    }

    /// Displacement over the last step.
    public var displacement: CGPoint { position - previousPosition }

    public var isPinned: Bool { inverseMass == 0 }

    /// Sets the implied velocity, in points per second, for a given step length.
    public mutating func setVelocity(_ velocity: CGPoint, timeStep: Double) {
        previousPosition = position - (velocity * timeStep)
    }
}
