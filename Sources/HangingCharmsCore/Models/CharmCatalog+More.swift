import Foundation

// The collections added in 1.2. All original artwork, drawn at run time.

extension CharmCatalog {
    // MARK: - Zodiac

    /// Twelve signs, each set on a face in the colour of its element.
    static let zodiac: [CharmDefinition] = {
        let signs: [(id: String, name: String, glyph: String, dates: String, element: String)] = [
            ("aries", "Aries", "\u{2648}", "21 March to 19 April", "fire"),
            ("taurus", "Taurus", "\u{2649}", "20 April to 20 May", "earth"),
            ("gemini", "Gemini", "\u{264A}", "21 May to 20 June", "air"),
            ("cancer", "Cancer", "\u{264B}", "21 June to 22 July", "water"),
            ("leo", "Leo", "\u{264C}", "23 July to 22 August", "fire"),
            ("virgo", "Virgo", "\u{264D}", "23 August to 22 September", "earth"),
            ("libra", "Libra", "\u{264E}", "23 September to 22 October", "air"),
            ("scorpio", "Scorpio", "\u{264F}", "23 October to 21 November", "water"),
            ("sagittarius", "Sagittarius", "\u{2650}", "22 November to 21 December", "fire"),
            ("capricorn", "Capricorn", "\u{2651}", "22 December to 19 January", "earth"),
            ("aquarius", "Aquarius", "\u{2652}", "20 January to 18 February", "air"),
            ("pisces", "Pisces", "\u{2653}", "19 February to 20 March", "water"),
        ]
        return signs.map { sign in
            let face: CharmFinish = switch sign.element {
            case "fire": .enamelRed
            case "earth": .enamelGreen
            case "air": .pearl
            default: .enamelBlue
            }
            return CharmDefinition(
                "zodiac-\(sign.id)", sign.name, .zodiac,
                // U+FE0E asks for the text form of the sign, never the emoji.
                .glyph(sign.glyph + "\u{FE0E}", font: .symbols, finish: .gold, face: face),
                mass: 4.4, blurb: "\(sign.dates). A \(sign.element) sign."
            )
        }
    }()

    // MARK: - Birthstones

    static let birthstones: [CharmDefinition] = {
        let stones: [(month: String, stone: String, cut: GemCut, colour: UInt32, setting: CharmFinish, note: String)] = [
            ("January", "Garnet", .round, 0x8E1B2E, .gold, "deep red, for constancy"),
            ("February", "Amethyst", .oval, 0x8E5CC9, .silver, "violet, for calm"),
            ("March", "Aquamarine", .emerald, 0x7FD4E6, .silver, "sea blue, for courage"),
            ("April", "Diamond", .round, 0xE8F3FF, .silver, "clear and bright, for strength"),
            ("May", "Emerald", .emerald, 0x1FA35B, .gold, "green, for growth"),
            ("June", "Pearl", .cabochon, 0xF4EEE6, .silver, "soft white, for purity"),
            ("July", "Ruby", .heart, 0xD3122F, .gold, "red, for passion"),
            ("August", "Peridot", .cushion, 0xA6D13B, .gold, "lime green, for good fortune"),
            ("September", "Sapphire", .pear, 0x1E4FC2, .silver, "blue, for wisdom"),
            ("October", "Opal", .opal, 0xEDE7F2, .silver, "a play of colour, for hope"),
            ("November", "Topaz", .marquise, 0xF2A93B, .gold, "golden, for warmth"),
            ("December", "Turquoise", .cabochon, 0x2EC4B6, .silver, "blue green, for protection"),
        ]
        return stones.map { stone in
            CharmDefinition(
                "stone-\(stone.month.lowercased())", stone.stone, .birthstones,
                .gem(stone.cut, color: RGBA(hex: stone.colour), setting: stone.setting),
                mass: 3.6, size: 0.95, sound: stone.cut == .cabochon ? .ceramic : .glass,
                blurb: "The \(stone.month) birthstone: \(stone.note)."
            )
        }
    }()

    // MARK: - Initials

    /// A to Z in gold on black enamel.
    static let initials: [CharmDefinition] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { letter in
        CharmDefinition(
            "letter-\(String(letter).lowercased())", "Letter \(letter)", .initials,
            .glyph(String(letter), font: .serif, finish: .gold, face: .obsidian),
            mass: 4.2, size: 0.9, blurb: "A gold \(letter) on black enamel. Hang your initials, or a name."
        )
    }

    // MARK: - Themed collections

    static let celebration: [CharmDefinition] = [
        CharmDefinition("balloon", "Balloon", .celebration, .cutout(symbol: "balloon.fill", finish: .enamelRed), mass: 2.4, blurb: "Up, up and away."),
        CharmDefinition("party-popper", "Party Popper", .celebration, .cutout(symbol: "party.popper.fill", finish: .gold), mass: 3.2, blurb: "For the moment worth marking."),
        CharmDefinition("fireworks", "Fireworks", .celebration, .cutout(symbol: "fireworks", finish: .enamelPurple), mass: 2.8, size: 1.05, blurb: "New year, new start."),
        CharmDefinition("cake", "Birthday Cake", .celebration, .cutout(symbol: "birthday.cake.fill", finish: .pearl), mass: 4, sound: .ceramic, blurb: "Make a wish."),
        CharmDefinition("cheers", "Cheers", .celebration, .cutout(symbol: "wineglass.fill", finish: .silver), mass: 3, sound: .glass, blurb: "Glasses up."),
        CharmDefinition("graduation", "Graduation", .celebration, .cutout(symbol: "graduationcap.fill", finish: .obsidian), mass: 3.8, blurb: "All that study, done."),
        CharmDefinition("applause", "Applause", .celebration, .medallion(symbol: "hands.clap.fill", finish: .gold, face: .enamelPurple), mass: 4.4, blurb: "A round of applause."),
        CharmDefinition("rosette", "Rosette", .celebration, .cutout(symbol: "rosette", finish: .bronze), mass: 3.4, blurb: "First place, every time."),
    ]

    static let food: [CharmDefinition] = [
        CharmDefinition("carrot", "Carrot", .food, .cutout(symbol: "carrot.fill", finish: .bronze), mass: 2.8, blurb: "Good for your eyes, they say."),
        CharmDefinition("tea", "Cup of Tea", .food, .cutout(symbol: "mug.fill", finish: .pearl), mass: 4, sound: .ceramic, blurb: "Kettle on."),
        CharmDefinition("dinner", "Knife and Fork", .food, .cutout(symbol: "fork.knife", finish: .silver), mass: 3.2, blurb: "Dinner is served."),
        CharmDefinition("takeaway", "Takeaway", .food, .cutout(symbol: "takeoutbag.and.cup.and.straw.fill", finish: .enamelRed), mass: 3.4, size: 1.05, blurb: "Friday night sorted."),
        CharmDefinition("popcorn", "Popcorn", .food, .cutout(symbol: "popcorn.fill", finish: .enamelRed), mass: 2.8, blurb: "For movie night."),
        CharmDefinition("frying-pan", "Frying Pan", .food, .cutout(symbol: "frying.pan.fill", finish: .obsidian), mass: 4.6, size: 1.05, blurb: "Breakfast, done right."),
        CharmDefinition("water-bottle", "Water Bottle", .food, .cutout(symbol: "waterbottle.fill", finish: .enamelBlue), mass: 3, size: 0.95, blurb: "Stay hydrated."),
    ]

    static let travel: [CharmDefinition] = [
        CharmDefinition("globe", "Globe", .travel, .medallion(symbol: "globe.asia.australia.fill", finish: .silver, face: .enamelBlue), mass: 4.6, blurb: "The whole world, in your pocket."),
        CharmDefinition("map", "Map", .travel, .cutout(symbol: "map.fill", finish: .bronze), mass: 3.2, blurb: "X marks the spot."),
        CharmDefinition("tent", "Tent", .travel, .cutout(symbol: "tent.fill", finish: .enamelGreen), mass: 3.4, blurb: "A night under the stars."),
        CharmDefinition("sailboat", "Sailboat", .travel, .cutout(symbol: "sailboat.fill", finish: .silver), mass: 3.2, blurb: "Fair winds."),
        CharmDefinition("road-trip", "Road Trip", .travel, .cutout(symbol: "car.fill", finish: .enamelRed), mass: 4.2, size: 1.05, blurb: "Windows down, music up."),
        CharmDefinition("bicycle", "Bicycle", .travel, .cutout(symbol: "bicycle", finish: .silver), mass: 3, size: 1.1, blurb: "Two wheels, no hurry."),
        CharmDefinition("binoculars", "Binoculars", .travel, .cutout(symbol: "binoculars.fill", finish: .obsidian), mass: 4.2, blurb: "For the view from the top."),
        CharmDefinition("suitcase", "Suitcase", .travel, .cutout(symbol: "suitcase.fill", finish: .bronze), mass: 4.4, blurb: "Packed and ready."),
        CharmDefinition("beach", "Beach Umbrella", .travel, .cutout(symbol: "beach.umbrella.fill", finish: .enamelBlue), mass: 3, blurb: "Sun, sand and a good book."),
        CharmDefinition("tram", "Tram", .travel, .cutout(symbol: "tram.fill", finish: .gold), mass: 4.2, blurb: "Next stop, anywhere."),
        CharmDefinition("pin", "You Are Here", .travel, .cutout(symbol: "mappin.and.ellipse", finish: .enamelRed), mass: 3, blurb: "Wherever you are, that's the place."),
        CharmDefinition("ferry", "Ferry", .travel, .cutout(symbol: "ferry.fill", finish: .silver), mass: 4.2, size: 1.05, blurb: "Across the harbour."),
    ]

    static let sports: [CharmDefinition] = [
        CharmDefinition("football", "Football", .sports, .cutout(symbol: "soccerball", finish: .pearl), mass: 3.6, sound: .ceramic, blurb: "The beautiful game."),
        CharmDefinition("basketball", "Basketball", .sports, .cutout(symbol: "basketball.fill", finish: .bronze), mass: 3.8, blurb: "Nothing but net."),
        CharmDefinition("tennis", "Tennis", .sports, .cutout(symbol: "tennis.racket", finish: .enamelGreen), mass: 3, size: 1.05, blurb: "Game, set and match."),
        CharmDefinition("baseball", "Baseball", .sports, .cutout(symbol: "baseball.fill", finish: .pearl), mass: 3.6, sound: .ceramic, blurb: "Swing for the fences."),
        CharmDefinition("runner", "Runner", .sports, .cutout(symbol: "figure.run", finish: .gold), mass: 3, blurb: "One more kilometre."),
        CharmDefinition("gym", "Dumbbell", .sports, .cutout(symbol: "dumbbell.fill", finish: .obsidian), mass: 5.6, size: 1.05, blurb: "Stronger every day."),
        CharmDefinition("trophy", "Trophy", .sports, .cutout(symbol: "trophy.fill", finish: .gold), mass: 5, blurb: "Champion."),
        CharmDefinition("medal", "Medal", .sports, .cutout(symbol: "medal.fill", finish: .gold), mass: 4.6, blurb: "You earned it."),
        CharmDefinition("palette", "Paint Palette", .sports, .cutout(symbol: "paintpalette.fill", finish: .pearl), mass: 3.4, sound: .wood, blurb: "Every colour you need."),
        CharmDefinition("camera", "Camera", .sports, .cutout(symbol: "camera.fill", finish: .obsidian), mass: 4.4, blurb: "Say cheese."),
        CharmDefinition("book", "Book", .sports, .cutout(symbol: "book.fill", finish: .enamelRed), mass: 3.8, sound: .wood, blurb: "Just one more chapter."),
        CharmDefinition("puzzle", "Puzzle Piece", .sports, .cutout(symbol: "puzzlepiece.fill", finish: .enamelBlue), mass: 2.8, sound: .wood, blurb: "The piece that fits."),
        CharmDefinition("theatre", "Theatre", .sports, .cutout(symbol: "theatermasks.fill", finish: .gold), mass: 3.6, size: 1.05, blurb: "Comedy and tragedy."),
        CharmDefinition("headphones", "Headphones", .sports, .cutout(symbol: "headphones", finish: .silver), mass: 3.6, blurb: "Volume up."),
    ]

    static let weather: [CharmDefinition] = [
        CharmDefinition("cloud", "Cloud", .weather, .cutout(symbol: "cloud.fill", finish: .pearl), mass: 2.4, sound: .glass, blurb: "Light as air."),
        CharmDefinition("rain", "Rain", .weather, .cutout(symbol: "cloud.rain.fill", finish: .enamelBlue), mass: 2.8, sound: .glass, blurb: "Good for the garden."),
        CharmDefinition("storm", "Storm", .weather, .cutout(symbol: "cloud.bolt.fill", finish: .silver), mass: 3.2, blurb: "This too shall pass."),
        CharmDefinition("rainbow", "Rainbow", .weather, .cutout(symbol: "rainbow", finish: .enamelPurple), mass: 2.6, size: 1.05, blurb: "After the rain."),
        CharmDefinition("umbrella", "Umbrella", .weather, .cutout(symbol: "umbrella.fill", finish: .enamelRed), mass: 3, blurb: "Ready for anything."),
        CharmDefinition("tornado", "Tornado", .weather, .cutout(symbol: "tornado", finish: .silver), mass: 2.8, blurb: "A whirlwind of energy."),
        CharmDefinition("wind", "Wind", .weather, .cutout(symbol: "wind", finish: .silver), mass: 2.4, blurb: "Change is in the air."),
        CharmDefinition("sunrise", "Sunrise", .weather, .cutout(symbol: "sun.horizon.fill", finish: .gold), mass: 3.4, size: 1.05, blurb: "A new day."),
    ]

    /// Filling out two of the first collections.
    static let moreLoveAndSpirit: [CharmDefinition] = [
        CharmDefinition("love-letter", "Love Letter", .love, .cutout(symbol: "envelope.fill", finish: .roseGold), mass: 3, blurb: "Sealed with love."),
        CharmDefinition("meditation", "Meditation", .spirit, .cutout(symbol: "figure.mind.and.body", finish: .silver), mass: 3.4, sound: .bell, blurb: "Breathe in, breathe out."),
    ]

    static let moreAnimals: [CharmDefinition] = [
        CharmDefinition("ant", "Ant", .animals, .cutout(symbol: "ant.fill", finish: .obsidian), mass: 2.4, blurb: "Small, strong and busy."),
        CharmDefinition("lizard", "Lizard", .animals, .cutout(symbol: "lizard.fill", finish: .enamelGreen), mass: 2.8, blurb: "Sunning itself on a warm rock."),
        CharmDefinition("teddy", "Teddy Bear", .animals, .cutout(symbol: "teddybear.fill", finish: .bronze), mass: 3.2, sound: .wood, blurb: "An old friend."),
    ]
}
