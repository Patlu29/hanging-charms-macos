import CoreGraphics
import Foundation

/// Where the top of the rope hangs from.
public enum HangPoint: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Just under the menu bar, somewhere across the screen.
    case menuBar
    /// Under the camera housing on a MacBook with a notch; the menu bar elsewhere.
    case notch
    /// The top edge of the front window, following it as it moves.
    case frontWindow
    /// A spot the user chose by dragging the grapple there.
    case anywhere

    public var id: String { rawValue }

    public static let `default`: HangPoint = .menuBar

    public var displayName: String {
        switch self {
        case .menuBar: "Menu bar"
        case .notch: "Notch"
        case .frontWindow: "Front window"
        case .anywhere: "Anywhere"
        }
    }

    public var summary: String {
        switch self {
        case .menuBar: "Hangs just under the menu bar. Move it across with the slider."
        case .notch: "Hangs from the camera notch. On a display without one, from the middle of the menu bar."
        case .frontWindow: "Hangs from the top of whichever window is in front, and swings when you move it."
        case .anywhere: "Hangs wherever you drop the grapple. Drag the top of the rope to move it."
        }
    }
}

/// An idle sway, so the charm moves on its own.
public enum Breeze: String, Codable, Sendable, CaseIterable, Identifiable {
    case still, gentle, windy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .still: "Still"
        case .gentle: "Gentle"
        case .windy: "Windy"
        }
    }

    /// Peak sideways push as a fraction of gravity.
    public var strength: Double {
        switch self {
        case .still: 0
        case .gentle: 0.05
        case .windy: 0.16
        }
    }
}

public extension OverlayPlacement {
    /// Under the camera notch. `leftArea` and `rightArea` are the screen's
    /// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` (y-up, screen-local); a screen
    /// without a notch has neither, and the rope hangs from the middle of the menu bar.
    static func notchAnchor(screenFrame: CGRect, visibleFrame: CGRect, leftArea: CGRect?, rightArea: CGRect?) -> CGPoint {
        let menuBar = max(0, screenFrame.maxY - visibleFrame.maxY)
        guard let leftArea, let rightArea, rightArea.minX > leftArea.maxX else {
            return CGPoint(x: screenFrame.width / 2, y: menuBar)
        }
        let x = (leftArea.maxX + rightArea.minX) / 2
        return CGPoint(x: x, y: max(menuBar, leftArea.height))
    }

    /// From the top edge of a window. `window` is in CGWindowList coordinates (top-left
    /// origin of the primary display, y down); the result is in the overlay's canvas.
    /// Clamped so the rope always starts on this screen, below the menu bar.
    static func windowAnchor(window: CGRect, screenFrame: CGRect, visibleFrame: CGRect,
                             primaryHeight: Double, horizontal: Double) -> CGPoint {
        let fraction = min(max(horizontal, 0), 1)
        let inset = min(60, window.width * 0.15)
        let globalX = window.minX + inset + (window.width - 2 * inset) * fraction
        // Convert the window's top edge from CG (y down) to the canvas (y down from the
        // top of this screen).
        let screenTopCG = primaryHeight - screenFrame.maxY
        let x = globalX - screenFrame.minX
        let y = window.minY - screenTopCG
        let menuBar = max(0, screenFrame.maxY - visibleFrame.maxY)
        return CGPoint(
            x: min(max(x, 8), screenFrame.width - 8),
            y: min(max(y, menuBar), screenFrame.height * 0.85)
        )
    }

    /// A pinned spot, stored as fractions of the screen so it survives resolution changes.
    static func pinnedAnchor(pin: CGPoint, screenFrame: CGRect) -> CGPoint {
        CGPoint(x: min(max(pin.x, 0), 1) * screenFrame.width, y: min(max(pin.y, 0), 1) * screenFrame.height)
    }

    /// The fractions to store for a canvas point.
    static func pin(for canvasPoint: CGPoint, screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(canvasPoint.x / max(1, screenFrame.width), 0), 1),
            y: min(max(canvasPoint.y / max(1, screenFrame.height), 0), 0.9)
        )
    }
}

/// A steady pendulum swing the charm keeps up on its own.
public enum AutoSwing: String, Codable, Sendable, CaseIterable, Identifiable {
    case off, small, medium, large

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// How far out the swing goes either side of straight down, in radians.
    public var amplitude: Double {
        switch self {
        case .off: 0
        case .small: 0.16
        case .medium: 0.3
        case .large: 0.48
        }
    }
}

/// The pendulum maths behind ``AutoSwing``.
public enum Pendulum {
    /// The swing's amplitude from where the bob is and how fast it is moving: the angle
    /// at which all of its energy would be potential.
    /// - Parameters:
    ///   - angle: From straight down, in radians.
    ///   - angularSpeed: Radians per second.
    ///   - length: Pendulum length, in points.
    ///   - gravity: Points per second squared.
    public static func amplitude(angle: Double, angularSpeed: Double, length: Double, gravity: Double) -> Double {
        guard length > 0, gravity > 0 else { return abs(angle) }
        let cosine = cos(angle) - (length * angularSpeed * angularSpeed) / (2 * gravity)
        return acos(min(max(cosine, -1), 1))
    }
}

/// The gusts behind ``Breeze``: a few incommensurate waves, so the sway never repeats
/// in an obvious loop. Returns a multiplier in roughly -1...1.
public enum Gust {
    public static func value(at time: Double) -> Double {
        0.55 * sin(time * 0.71) + 0.3 * sin(time * 1.83 + 1.1) + 0.15 * sin(time * 4.27 + 2.3)
    }
}
