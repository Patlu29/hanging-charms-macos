import Foundation

/// The solver values that make one cord behave differently from another.
public struct RopePhysicsProfile: Equatable, Sendable {
    public var gravityScale: Double
    public var damping: Double
    public var maxStretchRatio: Double
    public var constraintIterations: Int
    public var stretchPasses: Int
    public var charmMassScale: Double
}

/// An RGBA colour with components in 0...1. Kept in Core so models stay AppKit-free.
public struct RGBA: Equatable, Hashable, Sendable, Codable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }
}

/// How a cord is drawn.
public struct RopeAppearance: Equatable, Sendable {
    public enum Pattern: String, Sendable, Codable, CaseIterable, Identifiable {
        case twisted, braided, chain, glowing, fine

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .twisted: "Twisted"
            case .braided: "Braided"
            case .chain: "Chain links"
            case .glowing: "Lit filament"
            case .fine: "Fine silk"
            }
        }
    }
    public var pattern: Pattern
    public var primary: RGBA
    public var secondary: RGBA
    /// Line width as a fraction of the charm unit.
    public var widthScale: Double
}

/// The nine cords a charm can hang on. Each has its own solver values, so a gold
/// chain swings differently from a thread because of its physics, not its picture.
public enum RopeStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case thread, leather, goldChain, silverChain, neon, spiderThread, midnightCord, templeThread, silverCord

    public var id: String { rawValue }

    public static let `default`: RopeStyle = .goldChain

    public var physics: RopePhysicsProfile {
        switch self {
        case .thread:       RopePhysicsProfile(gravityScale: 1.00, damping: 0.9990, maxStretchRatio: 1.020, constraintIterations: 256, stretchPasses: 256, charmMassScale: 1.00)
        case .leather:      RopePhysicsProfile(gravityScale: 1.08, damping: 0.9955, maxStretchRatio: 1.006, constraintIterations: 288, stretchPasses: 288, charmMassScale: 1.05)
        case .goldChain:    RopePhysicsProfile(gravityScale: 0.72, damping: 0.9992, maxStretchRatio: 1.004, constraintIterations: 320, stretchPasses: 320, charmMassScale: 1.40)
        case .silverChain:  RopePhysicsProfile(gravityScale: 0.84, damping: 0.9988, maxStretchRatio: 1.005, constraintIterations: 320, stretchPasses: 320, charmMassScale: 1.25)
        case .neon:         RopePhysicsProfile(gravityScale: 1.22, damping: 0.9997, maxStretchRatio: 1.030, constraintIterations: 224, stretchPasses: 224, charmMassScale: 0.78)
        case .spiderThread: RopePhysicsProfile(gravityScale: 1.16, damping: 0.9996, maxStretchRatio: 1.004, constraintIterations: 336, stretchPasses: 336, charmMassScale: 0.80)
        case .midnightCord: RopePhysicsProfile(gravityScale: 0.78, damping: 0.9986, maxStretchRatio: 1.007, constraintIterations: 304, stretchPasses: 304, charmMassScale: 1.32)
        case .templeThread: RopePhysicsProfile(gravityScale: 1.04, damping: 0.9982, maxStretchRatio: 1.026, constraintIterations: 232, stretchPasses: 232, charmMassScale: 0.92)
        case .silverCord:   RopePhysicsProfile(gravityScale: 0.94, damping: 0.9990, maxStretchRatio: 1.009, constraintIterations: 272, stretchPasses: 272, charmMassScale: 1.08)
        }
    }

    public var displayName: String {
        switch self {
        case .thread: "Thread"
        case .leather: "Leather"
        case .goldChain: "Gold Chain"
        case .silverChain: "Silver Chain"
        case .neon: "Neon"
        case .spiderThread: "Spider Thread"
        case .midnightCord: "Midnight Cord"
        case .templeThread: "Temple Thread"
        case .silverCord: "Silver Cord"
        }
    }

    public var summary: String {
        switch self {
        case .thread: "Twisted gold thread. Light, quick and quiet."
        case .leather: "A flat braid. Stiffer than thread, and settles sooner."
        case .goldChain: "Linked gold. The heaviest cord, and the slowest to swing."
        case .silverChain: "Linked silver. A chain's weight with more life in it."
        case .neon: "A lit filament. The lightest cord, with a little give."
        case .spiderThread: "Spun silk. The thinnest cord, and strong for its weight."
        case .midnightCord: "A dark braid. Heavy, quiet and slow to give up a swing."
        case .templeThread: "Twisted cotton in saffron and red. Soft, with some give."
        case .silverCord: "Woven silver. A chain's shine with a cord's quickness."
        }
    }

    public var appearance: RopeAppearance {
        switch self {
        case .thread:       RopeAppearance(pattern: .twisted, primary: RGBA(hex: 0xD9A441), secondary: RGBA(hex: 0x9C6B1E), widthScale: 0.012)
        case .leather:      RopeAppearance(pattern: .braided, primary: RGBA(hex: 0x7A4A2A), secondary: RGBA(hex: 0x4E2D18), widthScale: 0.016)
        case .goldChain:    RopeAppearance(pattern: .chain, primary: RGBA(hex: 0xF2C14E), secondary: RGBA(hex: 0xA87A16), widthScale: 0.018)
        case .silverChain:  RopeAppearance(pattern: .chain, primary: RGBA(hex: 0xE4E7EB), secondary: RGBA(hex: 0x8C939C), widthScale: 0.016)
        case .neon:         RopeAppearance(pattern: .glowing, primary: RGBA(hex: 0x6CF7FF), secondary: RGBA(hex: 0xC86BFF), widthScale: 0.008)
        case .spiderThread: RopeAppearance(pattern: .fine, primary: RGBA(hex: 0xF4F4F6, alpha: 0.95), secondary: RGBA(hex: 0xB8BCC4, alpha: 0.6), widthScale: 0.004)
        case .midnightCord: RopeAppearance(pattern: .braided, primary: RGBA(hex: 0x23263A), secondary: RGBA(hex: 0x4B5175), widthScale: 0.016)
        case .templeThread: RopeAppearance(pattern: .twisted, primary: RGBA(hex: 0xF5A623), secondary: RGBA(hex: 0xD0301E), widthScale: 0.013)
        case .silverCord:   RopeAppearance(pattern: .twisted, primary: RGBA(hex: 0xD5D9DF), secondary: RGBA(hex: 0x7D848E), widthScale: 0.013)
        }
    }
}

/// How the rope feels at different times of day.
public enum RopeTimeProfile: String, CaseIterable, Codable, Sendable {
    case morning, afternoon, night

    public static let baseline: RopeTimeProfile = .afternoon

    /// Energy loss scale, release angle scale and rest speed scale.
    public var physics: (energyLossScale: Double, releaseAngleScale: Double, restSpeedScale: Double) {
        switch self {
        case .morning: (0.80, 1.14, 0.94)
        case .afternoon: (1, 1, 1)
        case .night: (1.30, 0.88, 1.10)
        }
    }

    public static func forHour(_ hour: Int) -> RopeTimeProfile {
        switch hour {
        case 5..<12: .morning
        case 12..<18: .afternoon
        default: .night
        }
    }

    public static func forDate(_ date: Date, calendar: Calendar = .current) -> RopeTimeProfile {
        forHour(calendar.component(.hour, from: date))
    }
}
