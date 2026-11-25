import CoreGraphics
import Foundation
import Testing
@testable import HangingCharmsCore

@Suite struct CustomisationTests {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test func olderDocumentsGetCustomisationDefaults() throws {
        let settings = try decode(#"{"ropeStyle":"neon","charmIDs":["heart"]}"#)
        #expect(settings.ropeThickness == 1)
        #expect(settings.ropePattern == nil)
        #expect(settings.showPin)
        #expect(settings.glowBreathing)
        #expect(settings.charmScales.isEmpty)
        #expect(settings.swingWeight == 1 && settings.settleSpeed == 1 && settings.hangDrop == 0)
    }

    @Test func customisationRoundTrips() {
        var settings = AppSettings()
        settings.customRopeColors = true
        settings.ropePrimary = RGBA(hex: 0x112233)
        settings.ropeSecondary = RGBA(hex: 0x445566)
        settings.ropeThickness = 2.2
        settings.ropePattern = .chain
        settings.showPin = false
        settings.ropeGlow = true
        settings.customGlowColor = true
        settings.glowColor = RGBA(hex: 0x00FF88)
        settings.glowIntensity = 0.4
        settings.glowSize = 1.8
        settings.glowBreathing = false
        settings.setScale(1.4, for: "heart")
        settings.charmShadow = false
        settings.swingWeight = 1.3
        settings.settleSpeed = 2
        settings.hangDrop = 120
        #expect(AppSettings.decode(settings.encoded()) == settings)
    }

    @Test func outOfRangeCustomisationIsClamped() throws {
        let json = #"""
        {"ropeThickness":40,"glowIntensity":-2,"glowSize":99,"swingWeight":0,"settleSpeed":100,"hangDrop":-50,
         "charmScales":{"heart":9,"star":0.01},"ropePrimary":{"r":4,"g":-1,"b":0.5,"a":2},"ropePattern":"zigzag"}
        """#
        let settings = try decode(json)
        #expect(settings.ropeThickness == AppSettings.ropeThicknessRange.upperBound)
        #expect(settings.glowIntensity == AppSettings.glowIntensityRange.lowerBound)
        #expect(settings.glowSize == AppSettings.glowSizeRange.upperBound)
        #expect(settings.swingWeight == AppSettings.swingWeightRange.lowerBound)
        #expect(settings.settleSpeed == AppSettings.settleSpeedRange.upperBound)
        #expect(settings.hangDrop == 0)
        #expect(settings.charmScales["heart"] == AppSettings.charmScaleRange.upperBound)
        #expect(settings.charmScales["star"] == AppSettings.charmScaleRange.lowerBound)
        #expect(settings.ropePrimary == RGBA(1, 0, 0.5, 1))
        #expect(settings.ropePattern == nil)
    }

    @Test func charmScaleDefaultsToOneAndDropsWhenReset() {
        var settings = AppSettings()
        #expect(settings.scale(for: "heart") == 1)
        settings.setScale(1.3, for: "heart")
        #expect(settings.scale(for: "heart") == 1.3)
        settings.setScale(1, for: "heart")
        #expect(settings.charmScales.isEmpty)
        settings.setScale(7, for: "star")
        #expect(settings.scale(for: "star") == AppSettings.charmScaleRange.upperBound)
    }

    @Test func pruneDropsScalesForMissingCharms() {
        var settings = AppSettings()
        settings.setScale(1.2, for: "custom:gone")
        settings.setScale(1.2, for: "heart")
        settings.prune(validIDs: ["heart", CharmCatalog.defaultID])
        #expect(settings.charmScales.keys.sorted() == ["heart"])
    }

    @Test func resolvedAppearanceAppliesOverrides() {
        var settings = AppSettings()
        settings.ropeStyle = .thread
        #expect(settings.resolvedRopeAppearance == RopeStyle.thread.appearance)
        settings.customRopeColors = true
        settings.ropePrimary = RGBA(hex: 0xFF0000)
        settings.ropePattern = .glowing
        settings.ropeThickness = 2
        let look = settings.resolvedRopeAppearance
        #expect(look.primary == RGBA(hex: 0xFF0000))
        #expect(look.pattern == .glowing)
        #expect(abs(look.widthScale - RopeStyle.thread.appearance.widthScale * 2) < 1e-12)
    }

    @Test func hangDropLowersTheAnchorWithinTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 945)
        #expect(OverlayPlacement.anchor(screenFrame: screen, visibleFrame: visible, horizontal: 0.5, drop: 100).y == 137)
        #expect(OverlayPlacement.anchor(screenFrame: screen, visibleFrame: visible, horizontal: 0.5, drop: 5000).y == 37 + 472.5)
    }

    @Test func swingWeightAndSettleSpeedScaleThePhysics() {
        let base = RopeConfiguration.make(unit: 260, style: .thread)
        let tuned = RopeConfiguration.make(unit: 260, style: .thread, swingWeight: 1.5, settleSpeed: 2)
        #expect(abs(tuned.gravity - base.gravity * 1.5) < 1e-9)
        #expect(abs((1 - tuned.damping) - (1 - base.damping) * 2) < 1e-12)
    }

    @Test func quickSettleSettlesSooner() {
        func secondsToSleep(_ settle: Double) -> Int {
            let configuration = RopeConfiguration.make(unit: 260, style: .thread, settleSpeed: settle)
            let rope = RopeSimulation(configuration: configuration, anchor: .zero, startAngle: 0.6)
            for frame in 1...(60 * 300) {
                rope.step(deltaTime: 1 / 60)
                if rope.isSleeping { return frame }
            }
            return .max
        }
        #expect(secondsToSleep(3) < secondsToSleep(1))
    }

    @Test func largerCharmScaleMakesALargerSlot() {
        let configuration = RopeConfiguration.make(unit: 260)
        let normal = CharmStackLayout.resolve(metrics: [.default], configuration: configuration)
        let big = CharmStackLayout.resolve(metrics: [CharmMetrics(mass: 4, sizeScale: 1.5)], configuration: configuration)
        #expect(abs(big.slots[0].radius / normal.slots[0].radius - 1.5) < 1e-9)
    }
}
