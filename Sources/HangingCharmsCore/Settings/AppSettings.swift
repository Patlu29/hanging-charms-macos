import CoreGraphics
import Foundation

/// Where the overlay sits.
public enum OverlayLevel: String, Codable, Sendable, CaseIterable {
    /// Above every app's windows.
    case aboveAll
    /// Behind every window, on the desktop.
    case desktop

    public var displayName: String {
        switch self {
        case .aboveAll: "Always on top"
        case .desktop: "On the desktop"
        }
    }
}

/// Every user preference, as one value. Decoding is tolerant: a missing key takes its
/// default, an out-of-range number is clamped, and unknown keys are ignored, so a
/// settings document from any build loads in any other.
public struct AppSettings: Equatable, Sendable, Codable {
    public static let schemaVersion = 1

    /// Charm IDs from the top of the rope down. Built-in IDs, or `custom:<uuid>`.
    public var charmIDs: [String] = [CharmCatalog.defaultID]
    public var ropeStyle: RopeStyle = .default
    public var ropeLength: Double = 1
    public var charmSize: Double = 1
    /// Where the rope hangs across the screen, 0 (left) to 1 (right).
    public var horizontalPosition: Double = 0.82
    /// The display's `localizedName` + index, or nil for the main display.
    public var displayKey: String?
    public var opacity: Double = 1
    public var level: OverlayLevel = .aboveAll
    public var isVisible = true
    public var glow = true
    public var sounds = true
    public var volume: Double = 0.6
    public var elastic = false
    public var mouseReactive = true
    public var timeOfDay = true
    public var hideInFullScreen = true
    public var launchAtLogin = false
    public var reduceMotion = false
    public var favourites: [String] = []
    public var recents: [String] = []

    public init() {}

    public static let ropeLengthRange = 0.5...1.8
    public static let charmSizeRange = 0.5...1.6
    public static let opacityRange = 0.3...1.0
    public static let volumeRange = 0.0...1.0
    public static let recentsLimit = 12

    // MARK: - Mutations with rules

    /// Adds a charm to the bottom of the rope, or replaces the stack when full.
    public mutating func hang(_ id: String, adding: Bool) {
        if adding {
            if charmIDs.count >= CharmStackLayout.maximumCharms { charmIDs.removeLast() }
            charmIDs.append(id)
        } else {
            charmIDs = [id]
        }
        noteRecent(id)
    }

    public mutating func removeCharm(at index: Int) {
        guard charmIDs.indices.contains(index), charmIDs.count > 1 else { return }
        charmIDs.remove(at: index)
    }

    /// Moves a charm up (-1) or down (+1) the rope.
    public mutating func moveCharm(at index: Int, by offset: Int) {
        let target = index + offset
        guard charmIDs.indices.contains(index), charmIDs.indices.contains(target) else { return }
        charmIDs.swapAt(index, target)
    }

    public mutating func toggleFavourite(_ id: String) {
        if let existing = favourites.firstIndex(of: id) {
            favourites.remove(at: existing)
        } else {
            favourites.append(id)
        }
    }

    public mutating func noteRecent(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > Self.recentsLimit { recents.removeLast(recents.count - Self.recentsLimit) }
    }

    /// Drops IDs that no longer resolve (a deleted custom charm), keeping at least one.
    public mutating func prune(validIDs: Set<String>) {
        charmIDs = charmIDs.filter(validIDs.contains)
        if charmIDs.isEmpty { charmIDs = [CharmCatalog.defaultID] }
        favourites = favourites.filter(validIDs.contains)
        recents = recents.filter(validIDs.contains)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, charmIDs, ropeStyle, ropeLength, charmSize, horizontalPosition, displayKey, opacity,
             level, isVisible, glow, sounds, volume, elastic, mouseReactive, timeOfDay, hideInFullScreen,
             launchAtLogin, reduceMotion, favourites, recents
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func clamp(_ value: Double?, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            guard let value, value.isFinite else { return fallback }
            return min(max(value, range.lowerBound), range.upperBound)
        }
        let ids = (try? c.decodeIfPresent([String].self, forKey: .charmIDs))?
            .filter { !$0.isEmpty }
            .prefix(CharmStackLayout.maximumCharms)
        charmIDs = ids.map(Array.init).flatMap { $0.isEmpty ? nil : $0 } ?? d.charmIDs
        ropeStyle = (try? c.decodeIfPresent(RopeStyle.self, forKey: .ropeStyle)) ?? d.ropeStyle
        ropeLength = clamp(try? c.decodeIfPresent(Double.self, forKey: .ropeLength), Self.ropeLengthRange, d.ropeLength)
        charmSize = clamp(try? c.decodeIfPresent(Double.self, forKey: .charmSize), Self.charmSizeRange, d.charmSize)
        horizontalPosition = clamp(try? c.decodeIfPresent(Double.self, forKey: .horizontalPosition), 0...1, d.horizontalPosition)
        displayKey = (try? c.decodeIfPresent(String.self, forKey: .displayKey)) ?? nil
        opacity = clamp(try? c.decodeIfPresent(Double.self, forKey: .opacity), Self.opacityRange, d.opacity)
        level = (try? c.decodeIfPresent(OverlayLevel.self, forKey: .level)) ?? d.level
        isVisible = (try? c.decodeIfPresent(Bool.self, forKey: .isVisible)) ?? d.isVisible
        glow = (try? c.decodeIfPresent(Bool.self, forKey: .glow)) ?? d.glow
        sounds = (try? c.decodeIfPresent(Bool.self, forKey: .sounds)) ?? d.sounds
        volume = clamp(try? c.decodeIfPresent(Double.self, forKey: .volume), Self.volumeRange, d.volume)
        elastic = (try? c.decodeIfPresent(Bool.self, forKey: .elastic)) ?? d.elastic
        mouseReactive = (try? c.decodeIfPresent(Bool.self, forKey: .mouseReactive)) ?? d.mouseReactive
        timeOfDay = (try? c.decodeIfPresent(Bool.self, forKey: .timeOfDay)) ?? d.timeOfDay
        hideInFullScreen = (try? c.decodeIfPresent(Bool.self, forKey: .hideInFullScreen)) ?? d.hideInFullScreen
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        reduceMotion = (try? c.decodeIfPresent(Bool.self, forKey: .reduceMotion)) ?? d.reduceMotion
        favourites = (try? c.decodeIfPresent([String].self, forKey: .favourites)) ?? d.favourites
        recents = Array(((try? c.decodeIfPresent([String].self, forKey: .recents)) ?? d.recents).prefix(Self.recentsLimit))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersion, forKey: .schemaVersion)
        try c.encode(charmIDs, forKey: .charmIDs)
        try c.encode(ropeStyle, forKey: .ropeStyle)
        try c.encode(ropeLength, forKey: .ropeLength)
        try c.encode(charmSize, forKey: .charmSize)
        try c.encode(horizontalPosition, forKey: .horizontalPosition)
        try c.encodeIfPresent(displayKey, forKey: .displayKey)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(level, forKey: .level)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(glow, forKey: .glow)
        try c.encode(sounds, forKey: .sounds)
        try c.encode(volume, forKey: .volume)
        try c.encode(elastic, forKey: .elastic)
        try c.encode(mouseReactive, forKey: .mouseReactive)
        try c.encode(timeOfDay, forKey: .timeOfDay)
        try c.encode(hideInFullScreen, forKey: .hideInFullScreen)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(reduceMotion, forKey: .reduceMotion)
        try c.encode(favourites, forKey: .favourites)
        try c.encode(recents, forKey: .recents)
    }

    // MARK: - Persistence helpers

    public static func decode(_ data: Data?) -> AppSettings {
        guard let data, let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

/// Pure placement maths for the overlay, in a window's y-down coordinates.
public enum OverlayPlacement {
    /// Base rope length as a fraction of the screen height.
    public static let unitFraction = 0.30

    /// The rope's anchor inside a window covering `screenFrame`, hanging just under
    /// the menu bar of `visibleFrame` (both in AppKit's y-up global coordinates).
    public static func anchor(screenFrame: CGRect, visibleFrame: CGRect, horizontal: Double) -> CGPoint {
        let fraction = min(max(horizontal, 0), 1)
        let margin = min(80, screenFrame.width * 0.05)
        let x = (visibleFrame.minX - screenFrame.minX) + margin + (visibleFrame.width - 2 * margin) * fraction
        let topInset = max(0, screenFrame.maxY - visibleFrame.maxY)
        return CGPoint(x: x, y: topInset)
    }

    /// The rope's base length for a screen, in points.
    public static func unit(for screenFrame: CGRect) -> Double {
        max(120, min(screenFrame.height * unitFraction, 420))
    }
}
