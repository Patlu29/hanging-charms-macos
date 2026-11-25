import Foundation

/// The metal a hook, grapple or bead is made of.
public enum AttachmentFinish: String, Codable, Sendable, CaseIterable, Identifiable {
    case matchRope, gold, silver, roseGold, bronze, black

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .matchRope: "Match the rope"
        case .gold: "Gold"
        case .silver: "Silver"
        case .roseGold: "Rose gold"
        case .bronze: "Bronze"
        case .black: "Black"
        }
    }

    /// Base, highlight and shadow colours. `rope` supplies the colours for ``matchRope``.
    public func palette(rope: RopeAppearance) -> (base: RGBA, highlight: RGBA, shadow: RGBA) {
        switch self {
        case .matchRope: (rope.primary, Self.lighten(rope.primary), rope.secondary)
        case .gold: (CharmFinish.gold.base, CharmFinish.gold.highlight, CharmFinish.gold.shadow)
        case .silver: (CharmFinish.silver.base, CharmFinish.silver.highlight, CharmFinish.silver.shadow)
        case .roseGold: (CharmFinish.roseGold.base, CharmFinish.roseGold.highlight, CharmFinish.roseGold.shadow)
        case .bronze: (CharmFinish.bronze.base, CharmFinish.bronze.highlight, CharmFinish.bronze.shadow)
        case .black: (CharmFinish.obsidian.base, CharmFinish.obsidian.highlight, CharmFinish.obsidian.shadow)
        }
    }

    static func lighten(_ colour: RGBA) -> RGBA {
        RGBA(colour.r + (1 - colour.r) * 0.55, colour.g + (1 - colour.g) * 0.55, colour.b + (1 - colour.b) * 0.55, colour.a)
    }
}

/// What joins each charm to the rope.
public enum HookStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The cord tied straight on with a small knot. No metal at all.
    case knot
    case sHook
    case fishHook
    case lobsterClasp
    case carabiner
    /// The classic round jump ring.
    case jumpRing

    public var id: String { rawValue }

    public static let `default`: HookStyle = .knot

    public var displayName: String {
        switch self {
        case .knot: "Tied knot"
        case .sHook: "S-hook"
        case .fishHook: "Fish hook"
        case .lobsterClasp: "Lobster clasp"
        case .carabiner: "Carabiner"
        case .jumpRing: "Jump ring"
        }
    }
}

/// What the top of the rope hangs from.
public enum GrappleStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case pin
    /// A three-pronged grappling hook caught over the menu bar.
    case grapplingHook
    case nail
    case binderClip
    case suctionCup
    case none

    public var id: String { rawValue }

    public static let `default`: GrappleStyle = .grapplingHook

    public var displayName: String {
        switch self {
        case .pin: "Pin"
        case .grapplingHook: "Grappling hook"
        case .nail: "Nail"
        case .binderClip: "Binder clip"
        case .suctionCup: "Suction cup"
        case .none: "Nothing"
        }
    }
}

/// Beads threaded along the rope.
public enum BeadDensity: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, few, many

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "None"
        case .few: "A few"
        case .many: "Many"
        }
    }

    /// Spacing between beads along the cord, as a fraction of the rope's base length.
    public var spacingFraction: Double? {
        switch self {
        case .none: nil
        case .few: 0.22
        case .many: 0.075
        }
    }
}

/// Where beads sit along a cord.
public enum BeadLayout {
    /// Distances along a cord of `length`, every `spacing`, leaving `margin` clear at the
    /// top (the grapple) and the bottom (the charm).
    public static func positions(length: Double, spacing: Double, margin: Double) -> [Double] {
        guard spacing > 0, length > 2 * margin else { return [] }
        let usable = length - 2 * margin
        let count = Int(usable / spacing) + 1
        let offset = margin + (usable - Double(count - 1) * spacing) / 2
        return (0..<count).map { offset + Double($0) * spacing }
    }
}
