import CoreGraphics
import Foundation
import Testing
@testable import HangingCharmsCore

@Suite struct CharmCatalogTests {
    @Test func idsAreUnique() {
        let ids = CharmCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyCollectionHasCharms() {
        for collection in CharmCollection.allCases {
            #expect(!CharmCatalog.charms(in: collection).isEmpty, "\(collection) is empty")
        }
    }

    @Test func defaultCharmExists() {
        #expect(CharmCatalog.charm(id: CharmCatalog.defaultID) != nil)
    }

    @Test func metricsAreSane() {
        for charm in CharmCatalog.all {
            #expect((1.5...8).contains(charm.metrics.mass), "\(charm.id) mass")
            #expect((0.7...1.3).contains(charm.metrics.sizeScale), "\(charm.id) size")
            #expect(!charm.blurb.isEmpty)
        }
    }

    @Test func searchMatchesNameCollectionAndDescription() {
        #expect(CharmCatalog.search("clover").map(\.id) == ["clover"])
        #expect(CharmCatalog.search("CELESTIAL").count == CharmCatalog.charms(in: .celestial).count)
        #expect(CharmCatalog.search("blue glass").contains { $0.id == "drop" })
        #expect(CharmCatalog.search("").count == CharmCatalog.all.count)
        #expect(CharmCatalog.search("zzzz").isEmpty)
    }
}

@Suite struct SettingsTests {
    @Test func emptyDocumentGivesDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings == AppSettings())
    }

    @Test func corruptDocumentGivesDefaults() {
        #expect(AppSettings.decode(Data("not json".utf8)) == AppSettings())
        #expect(AppSettings.decode(nil) == AppSettings())
    }

    @Test func partialDocumentKeepsWhatItHas() throws {
        let json = #"{"ropeStyle":"neon","glow":false,"somethingFromTheFuture":42}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.ropeStyle == .neon)
        #expect(settings.glow == false)
        #expect(settings.sounds == AppSettings().sounds)
    }

    @Test func outOfRangeValuesAreClamped() throws {
        let json = #"{"ropeLength":99,"charmSize":-3,"opacity":0,"horizontalPosition":7,"volume":5}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.ropeLength == AppSettings.ropeLengthRange.upperBound)
        #expect(settings.charmSize == AppSettings.charmSizeRange.lowerBound)
        #expect(settings.opacity == AppSettings.opacityRange.lowerBound)
        #expect(settings.horizontalPosition == 1)
        #expect(settings.volume == 1)
    }

    @Test func unknownRopeStyleFallsBack() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"ropeStyle":"spaghetti"}"#.utf8))
        #expect(settings.ropeStyle == .default)
    }

    @Test func tooManyCharmsAreTrimmed() throws {
        let json = #"{"charmIDs":["a","b","c","d","e"]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.charmIDs == ["a", "b", "c"])
    }

    @Test func roundTripIsLossless() {
        var settings = AppSettings()
        settings.charmIDs = ["heart", "star"]
        settings.ropeStyle = .silverCord
        settings.displayKey = "Studio Display#1"
        settings.favourites = ["heart"]
        #expect(AppSettings.decode(settings.encoded()) == settings)
    }

    @Test func hangingAddsAndReplaces() {
        var settings = AppSettings()
        settings.hang("heart", adding: false)
        #expect(settings.charmIDs == ["heart"])
        settings.hang("star", adding: true)
        settings.hang("sun", adding: true)
        settings.hang("key", adding: true)
        #expect(settings.charmIDs == ["heart", "star", "key"])
        #expect(settings.recents.first == "key")
    }

    @Test func movingAndRemovingCharms() {
        var settings = AppSettings()
        settings.charmIDs = ["a", "b", "c"]
        settings.moveCharm(at: 2, by: -1)
        #expect(settings.charmIDs == ["a", "c", "b"])
        settings.moveCharm(at: 0, by: -1)
        #expect(settings.charmIDs == ["a", "c", "b"])
        settings.removeCharm(at: 0)
        settings.removeCharm(at: 0)
        settings.removeCharm(at: 0)
        #expect(settings.charmIDs == ["b"])
    }

    @Test func favouritesToggle() {
        var settings = AppSettings()
        settings.toggleFavourite("heart")
        #expect(settings.favourites == ["heart"])
        settings.toggleFavourite("heart")
        #expect(settings.favourites.isEmpty)
    }

    @Test func pruneDropsMissingCustomCharms() {
        var settings = AppSettings()
        settings.charmIDs = ["custom:gone"]
        settings.favourites = ["custom:gone", "heart"]
        settings.prune(validIDs: ["heart", CharmCatalog.defaultID])
        #expect(settings.charmIDs == [CharmCatalog.defaultID])
        #expect(settings.favourites == ["heart"])
    }

    @Test func recentsAreCapped() {
        var settings = AppSettings()
        for index in 0..<30 { settings.noteRecent("c\(index)") }
        #expect(settings.recents.count == AppSettings.recentsLimit)
        #expect(settings.recents.first == "c29")
    }
}

@Suite struct PlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 945)

    @Test func hangsBelowTheMenuBar() {
        let anchor = OverlayPlacement.anchor(screenFrame: screen, visibleFrame: visible, horizontal: 0.5)
        #expect(anchor.y == 37)
        #expect(abs(anchor.x - 756) < 0.001)
    }

    @Test func horizontalIsClampedInsideTheMargins() {
        let left = OverlayPlacement.anchor(screenFrame: screen, visibleFrame: visible, horizontal: -1)
        let right = OverlayPlacement.anchor(screenFrame: screen, visibleFrame: visible, horizontal: 2)
        #expect(left.x > 0)
        #expect(right.x < screen.width)
    }

    @Test func secondaryDisplayWithNegativeOriginUsesLocalCoordinates() {
        let other = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let anchor = OverlayPlacement.anchor(screenFrame: other, visibleFrame: other, horizontal: 0)
        #expect(anchor.x >= 0 && anchor.x < 1920)
        #expect(anchor.y == 0)
    }

    @Test func unitIsBounded() {
        #expect(OverlayPlacement.unit(for: CGRect(x: 0, y: 0, width: 100, height: 100)) == 120)
        #expect(OverlayPlacement.unit(for: CGRect(x: 0, y: 0, width: 6000, height: 3000)) == 420)
    }
}

@Suite struct SoundSynthesizerTests {
    @Test(arguments: SoundMaterial.allCases)
    func everyMaterialIsFiniteBoundedAndDecays(material: SoundMaterial) {
        let samples = SoundSynthesizer.render(material: material, intensity: 1)
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
        let peak = samples.prefix(samples.count / 10).map { abs($0) }.max() ?? 0
        let tail = samples.suffix(samples.count / 20).map { abs($0) }.max() ?? 0
        #expect(peak > 0.1)
        #expect(tail < peak * 0.05)
    }

    @Test func intensityScalesLevel() {
        let soft = SoundSynthesizer.render(material: .metal, intensity: 0.2).map { abs($0) }.max() ?? 0
        let hard = SoundSynthesizer.render(material: .metal, intensity: 1).map { abs($0) }.max() ?? 0
        #expect(hard > soft * 3)
    }

    @Test func silentAtZeroIntensity() {
        #expect(SoundSynthesizer.render(material: .bell, intensity: 0).allSatisfy { $0 == 0 })
    }
}
