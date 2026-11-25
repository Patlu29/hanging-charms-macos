import CoreGraphics
import Foundation

// Small vector helpers over CGPoint. The solver is plain arithmetic on these.

public extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: CGPoint, rhs: Double) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }
    static func / (lhs: CGPoint, rhs: Double) -> CGPoint { CGPoint(x: lhs.x / rhs, y: lhs.y / rhs) }
    static func += (lhs: inout CGPoint, rhs: CGPoint) { lhs = lhs + rhs }
    static func -= (lhs: inout CGPoint, rhs: CGPoint) { lhs = lhs - rhs }

    var magnitude: Double { (x * x + y * y).squareRoot() }

    func distance(to other: CGPoint) -> Double { (self - other).magnitude }

    /// The same direction, no longer than `limit`.
    func limited(to limit: Double) -> CGPoint {
        let length = magnitude
        guard length > limit, length > 0 else { return self }
        return self * (limit / length)
    }

    var normalized: CGPoint {
        let length = magnitude
        return length > .ulpOfOne ? self / length : CGPoint(x: 0, y: 1)
    }

    /// Rotated anticlockwise (in y-up terms) by `angle` radians.
    func rotated(by angle: Double) -> CGPoint {
        let c = cos(angle), s = sin(angle)
        return CGPoint(x: x * c - y * s, y: x * s + y * c)
    }

    func dot(_ other: CGPoint) -> Double { x * other.x + y * other.y }
}
