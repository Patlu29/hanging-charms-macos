import Foundation

/// What a charm sounds like when it is knocked.
public enum SoundMaterial: String, Codable, Sendable, CaseIterable {
    case metal, glass, wood, ceramic, bell
}

/// The metal or enamel a charm is finished in.
public enum CharmFinish: String, Codable, Sendable, CaseIterable {
    case gold, silver, roseGold, bronze, enamelBlue, enamelRed, enamelGreen, enamelPurple, pearl, obsidian

    public var base: RGBA {
        switch self {
        case .gold: RGBA(hex: 0xE8B84A)
        case .silver: RGBA(hex: 0xC9CED6)
        case .roseGold: RGBA(hex: 0xE6A58E)
        case .bronze: RGBA(hex: 0xB0763B)
        case .enamelBlue: RGBA(hex: 0x2F6FDE)
        case .enamelRed: RGBA(hex: 0xD8343C)
        case .enamelGreen: RGBA(hex: 0x2FA35A)
        case .enamelPurple: RGBA(hex: 0x7B4BD6)
        case .pearl: RGBA(hex: 0xF3EEE6)
        case .obsidian: RGBA(hex: 0x2A2B33)
        }
    }

    public var highlight: RGBA {
        switch self {
        case .gold: RGBA(hex: 0xFFF0B8)
        case .silver: RGBA(hex: 0xFFFFFF)
        case .roseGold: RGBA(hex: 0xFFE1D6)
        case .bronze: RGBA(hex: 0xF0C08A)
        case .enamelBlue: RGBA(hex: 0x9CC2FF)
        case .enamelRed: RGBA(hex: 0xFF9C9C)
        case .enamelGreen: RGBA(hex: 0x9EE8B6)
        case .enamelPurple: RGBA(hex: 0xC9B0FF)
        case .pearl: RGBA(hex: 0xFFFFFF)
        case .obsidian: RGBA(hex: 0x6E7180)
        }
    }

    public var shadow: RGBA {
        switch self {
        case .gold: RGBA(hex: 0x8A5F12)
        case .silver: RGBA(hex: 0x6C727C)
        case .roseGold: RGBA(hex: 0x9C5A48)
        case .bronze: RGBA(hex: 0x5E3714)
        case .enamelBlue: RGBA(hex: 0x163C86)
        case .enamelRed: RGBA(hex: 0x7E141A)
        case .enamelGreen: RGBA(hex: 0x145C30)
        case .enamelPurple: RGBA(hex: 0x3B1F7A)
        case .pearl: RGBA(hex: 0xB8AE9F)
        case .obsidian: RGBA(hex: 0x0C0C10)
        }
    }

    public var defaultSound: SoundMaterial {
        switch self {
        case .gold, .silver, .roseGold, .bronze: .metal
        case .enamelBlue, .enamelRed, .enamelGreen, .enamelPurple: .ceramic
        case .pearl: .glass
        case .obsidian: .glass
        }
    }
}

/// How a charm's artwork is made. All of it is original and drawn at run time.
public enum CharmArt: Equatable, Sendable {
    /// A symbol cut out of solid metal or enamel.
    case cutout(symbol: String, finish: CharmFinish)
    /// A round coin with the symbol embossed on its face.
    case medallion(symbol: String, finish: CharmFinish, face: CharmFinish)
    /// One of the hand-drawn shapes.
    case drawn(DrawnShape)
    /// A coin with a letter or a sign set on its face.
    case glyph(String, font: GlyphFont, finish: CharmFinish, face: CharmFinish)
    /// A cut gemstone in a metal setting.
    case gem(GemCut, color: RGBA, setting: CharmFinish)
}

/// The typeface a glyph charm is set in.
public enum GlyphFont: String, Sendable {
    /// A bold serif, for initials.
    case serif
    /// Apple's symbol font, for zodiac signs.
    case symbols
}

/// How a gemstone is cut.
public enum GemCut: String, Sendable, CaseIterable {
    case round, oval, emerald, cushion, heart, pear, marquise
    /// Polished smooth and domed, for opaque stones and pearls.
    case cabochon
    /// A cabochon showing a play of colour, for opal.
    case opal
}

/// Charms that are drawn as vector paths rather than from a symbol.
public enum DrawnShape: String, Sendable, CaseIterable {
    case evilEye, crescent, fourLeafClover, horseshoe, heart, star, sun, crystal, luckySeven, lotus, planet, dreamcatcher
}

/// A group of charms in the Library.
public enum CharmCollection: String, CaseIterable, Codable, Sendable, Identifiable {
    case protection, luck, celestial, nature, love, spirit, classics, animals

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .protection: "Protection"
        case .luck: "Luck"
        case .celestial: "Celestial"
        case .nature: "Nature"
        case .love: "Love"
        case .spirit: "Spirit"
        case .classics: "Classics"
        case .animals: "Animals"
        }
    }
}

/// One built-in charm.
public struct CharmDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let collection: CharmCollection
    public let art: CharmArt
    public let metrics: CharmMetrics
    public let sound: SoundMaterial
    public let blurb: String

    public init(_ id: String, _ name: String, _ collection: CharmCollection, _ art: CharmArt,
                mass: Double = 4, size: Double = 1, sound: SoundMaterial? = nil, blurb: String) {
        self.id = id
        self.name = name
        self.collection = collection
        self.art = art
        self.metrics = CharmMetrics(mass: mass, sizeScale: size)
        self.blurb = blurb
        if let sound {
            self.sound = sound
        } else {
            switch art {
            case let .cutout(_, finish), let .medallion(_, finish, _), let .glyph(_, _, finish, _): self.sound = finish.defaultSound
            case .drawn: self.sound = .metal
            case .gem: self.sound = .glass
            }
        }
    }
}

/// The built-in Library.
public enum CharmCatalog {
    public static let all: [CharmDefinition] = [
        // Protection
        CharmDefinition("evil-eye", "Evil Eye", .protection, .drawn(.evilEye), mass: 3.6, size: 0.95, sound: .glass, blurb: "Glass nazar in layered blue, said to turn away a jealous glance."),
        CharmDefinition("hamsa", "Open Hand", .protection, .cutout(symbol: "hand.raised.fill", finish: .silver), mass: 4.2, size: 1.05, blurb: "An open palm raised in protection."),
        CharmDefinition("shield", "Shield", .protection, .cutout(symbol: "shield.fill", finish: .bronze), mass: 5, size: 1.0, blurb: "A small bronze shield for the days that need one."),
        CharmDefinition("all-seeing", "Watchful Eye", .protection, .medallion(symbol: "eye.fill", finish: .gold, face: .enamelBlue), mass: 4.4, blurb: "An enamelled eye that keeps watch."),
        CharmDefinition("padlock", "Padlock", .protection, .cutout(symbol: "lock.fill", finish: .gold), mass: 5.2, size: 0.9, blurb: "Keeps what matters safe."),
        CharmDefinition("dreamcatcher", "Dream Catcher", .protection, .drawn(.dreamcatcher), mass: 3, size: 1.1, sound: .wood, blurb: "A woven hoop to catch the bad dreams."),

        // Luck
        CharmDefinition("clover", "Four-Leaf Clover", .luck, .drawn(.fourLeafClover), mass: 3.2, sound: .ceramic, blurb: "One in ten thousand clovers has the fourth leaf."),
        CharmDefinition("horseshoe", "Horseshoe", .luck, .drawn(.horseshoe), mass: 5.4, blurb: "Hung points-up, so the luck cannot run out."),
        CharmDefinition("lucky-seven", "Lucky Seven", .luck, .drawn(.luckySeven), mass: 4.4, blurb: "The number that always seems to come up."),
        CharmDefinition("dice", "Die", .luck, .cutout(symbol: "die.face.5.fill", finish: .pearl), mass: 3.8, size: 0.85, sound: .ceramic, blurb: "Roll for it."),
        CharmDefinition("ladybug", "Ladybird", .luck, .cutout(symbol: "ladybug.fill", finish: .enamelRed), mass: 2.8, size: 0.85, blurb: "Count the spots for the months of good luck."),
        CharmDefinition("coin", "Lucky Coin", .luck, .medallion(symbol: "dollarsign", finish: .gold, face: .gold), mass: 5.6, size: 0.9, blurb: "A coin found heads-up."),

        // Celestial
        CharmDefinition("crescent", "Crescent Moon", .celestial, .drawn(.crescent), mass: 3.8, blurb: "A new moon for a new start."),
        CharmDefinition("star", "Star", .celestial, .drawn(.star), mass: 3.6, blurb: "Five points, polished bright."),
        CharmDefinition("sun", "Sun", .celestial, .drawn(.sun), mass: 4.6, blurb: "Rays of brushed gold."),
        CharmDefinition("planet", "Ringed Planet", .celestial, .drawn(.planet), mass: 4.2, size: 1.05, sound: .glass, blurb: "A small world with its own ring."),
        CharmDefinition("moon-stars", "Night Sky", .celestial, .medallion(symbol: "moon.stars.fill", finish: .silver, face: .obsidian), mass: 4.6, blurb: "Moon and stars on a dark face."),
        CharmDefinition("sparkles", "Sparkle", .celestial, .cutout(symbol: "sparkles", finish: .silver), mass: 2.6, size: 0.9, sound: .glass, blurb: "A little light, caught."),
        CharmDefinition("bolt", "Lightning", .celestial, .cutout(symbol: "bolt.fill", finish: .gold), mass: 3.2, size: 0.95, blurb: "Quick as a flash."),

        // Nature
        CharmDefinition("leaf", "Leaf", .nature, .cutout(symbol: "leaf.fill", finish: .enamelGreen), mass: 2.6, blurb: "A leaf that never falls."),
        CharmDefinition("snowflake", "Snowflake", .nature, .cutout(symbol: "snowflake", finish: .silver), mass: 2.8, sound: .glass, blurb: "No two the same."),
        CharmDefinition("flame", "Flame", .nature, .cutout(symbol: "flame.fill", finish: .enamelRed), mass: 2.8, size: 0.95, blurb: "Keeps the spark going."),
        CharmDefinition("drop", "Raindrop", .nature, .cutout(symbol: "drop.fill", finish: .enamelBlue), mass: 3, size: 0.85, sound: .glass, blurb: "A single drop of blue glass."),
        CharmDefinition("mountain", "Mountain", .nature, .medallion(symbol: "mountain.2.fill", finish: .bronze, face: .pearl), mass: 5, blurb: "For the climb."),
        CharmDefinition("crystal", "Crystal", .nature, .drawn(.crystal), mass: 4, size: 1.05, sound: .glass, blurb: "A faceted amethyst point."),

        // Love
        CharmDefinition("heart", "Heart", .love, .drawn(.heart), mass: 3.8, blurb: "Red enamel set in gold."),
        CharmDefinition("infinity", "Infinity", .love, .cutout(symbol: "infinity", finish: .roseGold), mass: 3, size: 1.05, blurb: "For always."),
        CharmDefinition("gift", "Gift", .love, .cutout(symbol: "gift.fill", finish: .enamelPurple), mass: 3.6, size: 0.9, blurb: "Something given, kept close."),
        CharmDefinition("heart-medal", "Locket", .love, .medallion(symbol: "heart.fill", finish: .roseGold, face: .enamelRed), mass: 4.8, blurb: "A locket with a heart on its face."),
        CharmDefinition("rose", "Bloom", .love, .cutout(symbol: "camera.macro", finish: .enamelRed), mass: 2.8, size: 0.95, sound: .ceramic, blurb: "A flower that keeps."),

        // Spirit
        CharmDefinition("lotus", "Lotus", .spirit, .drawn(.lotus), mass: 3.6, size: 1.05, sound: .bell, blurb: "Grows from mud, opens clean."),
        CharmDefinition("yin-yang", "Balance", .spirit, .cutout(symbol: "circle.lefthalf.filled", finish: .obsidian), mass: 4, size: 0.9, sound: .bell, blurb: "Light and dark in one circle."),
        CharmDefinition("peace", "Peace", .spirit, .medallion(symbol: "hand.wave.fill", finish: .silver, face: .enamelBlue), mass: 4.2, sound: .bell, blurb: "A raised hand in greeting."),
        CharmDefinition("seal", "Seal", .spirit, .cutout(symbol: "seal.fill", finish: .gold), mass: 4.4, sound: .bell, blurb: "A rosette of good intentions."),
        CharmDefinition("hands", "Blessing", .spirit, .medallion(symbol: "hands.sparkles.fill", finish: .gold, face: .pearl), mass: 4.6, sound: .bell, blurb: "Hands held up in thanks."),

        // Classics
        CharmDefinition("key", "Key", .classics, .cutout(symbol: "key.fill", finish: .bronze), mass: 4.6, blurb: "Opens the right door."),
        CharmDefinition("bell", "Bell", .classics, .cutout(symbol: "bell.fill", finish: .gold), mass: 5, sound: .bell, blurb: "Rings when it swings."),
        CharmDefinition("crown", "Crown", .classics, .cutout(symbol: "crown.fill", finish: .gold), mass: 5, size: 1.05, blurb: "For the one in charge."),
        CharmDefinition("music", "Note", .classics, .cutout(symbol: "music.note", finish: .obsidian), mass: 2.8, size: 0.95, blurb: "A quaver, held."),
        CharmDefinition("guitar", "Guitar", .classics, .cutout(symbol: "guitars.fill", finish: .bronze), mass: 3.4, size: 1.1, sound: .wood, blurb: "Two guitars, crossed."),
        CharmDefinition("plane", "Aeroplane", .classics, .cutout(symbol: "airplane", finish: .silver), mass: 3.2, blurb: "For the next trip."),
        CharmDefinition("controller", "Controller", .classics, .cutout(symbol: "gamecontroller.fill", finish: .obsidian), mass: 3.6, size: 1.05, sound: .wood, blurb: "Player one."),
        CharmDefinition("coffee", "Coffee", .classics, .cutout(symbol: "cup.and.saucer.fill", finish: .pearl), mass: 4, size: 0.95, sound: .ceramic, blurb: "First things first."),

        // Animals
        CharmDefinition("paw", "Paw Print", .animals, .cutout(symbol: "pawprint.fill", finish: .roseGold), mass: 3, size: 0.9, blurb: "For the friend at your feet."),
        CharmDefinition("cat", "Cat", .animals, .cutout(symbol: "cat.fill", finish: .obsidian), mass: 3.4, blurb: "Lands on its feet."),
        CharmDefinition("dog", "Dog", .animals, .cutout(symbol: "dog.fill", finish: .bronze), mass: 3.6, blurb: "Always pleased to see you."),
        CharmDefinition("bird", "Bird", .animals, .cutout(symbol: "bird.fill", finish: .enamelBlue), mass: 2.6, blurb: "A bluebird for happiness."),
        CharmDefinition("fish", "Fish", .animals, .cutout(symbol: "fish.fill", finish: .enamelPurple), mass: 2.8, blurb: "Swims the other way."),
        CharmDefinition("tortoise", "Tortoise", .animals, .cutout(symbol: "tortoise.fill", finish: .enamelGreen), mass: 4.8, sound: .ceramic, blurb: "Slow, steady, long-lived."),
        CharmDefinition("hare", "Hare", .animals, .cutout(symbol: "hare.fill", finish: .silver), mass: 3, blurb: "Quick on its feet."),
    ]

    public static let defaultID = "evil-eye"

    private static let index: [String: CharmDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func charm(id: String) -> CharmDefinition? { index[id] }

    public static func charms(in collection: CharmCollection) -> [CharmDefinition] {
        all.filter { $0.collection == collection }
    }

    /// Case- and diacritic-insensitive search over name, collection and description.
    public static func search(_ query: String, in charms: [CharmDefinition] = all) -> [CharmDefinition] {
        let terms = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return charms }
        return charms.filter { charm in
            let haystack = "\(charm.name) \(charm.collection.displayName) \(charm.blurb)"
            return terms.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
