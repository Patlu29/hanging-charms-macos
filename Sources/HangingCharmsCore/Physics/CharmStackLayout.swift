import Foundation

/// Mass and size of one charm, as the solver sees it.
public struct CharmMetrics: Equatable, Sendable, Codable {
    /// Relative to one rope node, which weighs 1.
    public var mass: Double
    /// Diameter multiplier on the standard charm size.
    public var sizeScale: Double

    public init(mass: Double = 4, sizeScale: Double = 1) {
        self.mass = mass
        self.sizeScale = sizeScale
    }

    public static let `default` = CharmMetrics()

    /// The standard charm diameter, as a fraction of the configuration's charm unit.
    public static let diameterFraction = 0.34
}

/// Where each charm on a stacked rope hangs and how large it is.
///
/// The top charm hangs where a single charm would. Every charm below it adds rope:
/// enough links for the charm above to fit, plus a small jump-ring gap, so stacking a
/// charm never squashes the ones already there.
public struct CharmStackLayout: Equatable, Sendable {
    public struct Slot: Equatable, Sendable {
        /// The rope node the charm's ring is tied to.
        public var node: Int
        /// Half the charm's drawn diameter, in points.
        public var radius: Double
        /// Mass after the rope style's scale.
        public var mass: Double
    }

    /// Charms from the anchor down.
    public var slots: [Slot]
    /// Nodes in the whole rope, anchor included.
    public var pointCount: Int

    /// Maximum charms on one rope.
    public static let maximumCharms = 3

    /// The empty space between one charm's bottom and the next charm's ring.
    public static func gap(for configuration: RopeConfiguration) -> Double {
        max(4, configuration.charmUnit * 0.03)
    }

    public static func resolve(
        metrics: [CharmMetrics],
        configuration: RopeConfiguration,
        charmSize: Double = 1,
        massScale: Double = 1
    ) -> CharmStackLayout {
        let stack = Array((metrics.isEmpty ? [.default] : metrics).prefix(maximumCharms))
        let base = configuration.charmUnit * CharmMetrics.diameterFraction * max(0.2, charmSize)
        let gap = gap(for: configuration)

        var slots: [Slot] = []
        var node = configuration.segmentCount
        for (index, charm) in stack.enumerated() {
            let radius = base * charm.sizeScale / 2
            slots.append(Slot(node: node, radius: radius, mass: max(0.1, charm.mass * massScale)))
            if index < stack.count - 1 {
                let span = (2 * radius) + gap
                node += max(2, Int((span / configuration.segmentLength).rounded(.up)))
            }
        }
        return CharmStackLayout(slots: slots, pointCount: node + 1)
    }
}
