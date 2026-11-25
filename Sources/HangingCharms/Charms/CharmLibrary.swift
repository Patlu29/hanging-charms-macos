import AppKit
import Observation
import HangingCharmsCore

/// A charm the overlay can hang, built-in or the user's own.
struct ResolvedCharm: Identifiable {
    enum Source {
        case builtIn(CharmDefinition)
        case custom(CGImage)
    }

    let id: String
    let name: String
    let detail: String
    let collectionName: String
    let metrics: CharmMetrics
    let sound: SoundMaterial
    let source: Source

    var isCustom: Bool {
        if case .custom = source { return true }
        return false
    }
}

/// One custom charm on disk.
struct CustomCharmRecord: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var created: Date
    var mass: Double
    var sizeScale: Double

    var charmID: String { CharmLibrary.customPrefix + id }
}

/// Resolves charm IDs, and owns the user's custom charms in Application Support.
@MainActor
@Observable
final class CharmLibrary {
    nonisolated static let customPrefix = "custom:"

    private(set) var customCharms: [CustomCharmRecord] = []
    @ObservationIgnored private var images: [String: CGImage] = [:]
    @ObservationIgnored private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HangingCharms", isDirectory: true)
            .appendingPathComponent("CustomCharms", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    private var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    private func imageURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).png") }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let records = try? JSONDecoder().decode([CustomCharmRecord].self, from: data) else {
            customCharms = []
            return
        }
        // Drop records whose picture has gone missing.
        customCharms = records.filter { FileManager.default.fileExists(atPath: imageURL($0.id).path) }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(customCharms) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    // MARK: - Resolving

    var validIDs: Set<String> {
        Set(CharmCatalog.all.map(\.id)).union(customCharms.map(\.charmID))
    }

    func resolve(_ id: String) -> ResolvedCharm? {
        if let definition = CharmCatalog.charm(id: id) {
            return ResolvedCharm(
                id: id, name: definition.name, detail: definition.blurb,
                collectionName: definition.collection.displayName,
                metrics: definition.metrics, sound: definition.sound, source: .builtIn(definition)
            )
        }
        guard id.hasPrefix(Self.customPrefix) else { return nil }
        let raw = String(id.dropFirst(Self.customPrefix.count))
        guard let record = customCharms.first(where: { $0.id == raw }), let image = customImage(raw) else { return nil }
        return ResolvedCharm(
            id: id, name: record.name, detail: "Your own charm, made from a picture.",
            collectionName: "My Charms",
            metrics: CharmMetrics(mass: record.mass, sizeScale: record.sizeScale),
            sound: .glass, source: .custom(image)
        )
    }

    func resolveOrDefault(_ id: String) -> ResolvedCharm {
        resolve(id) ?? resolve(CharmCatalog.defaultID)!
    }

    private func customImage(_ id: String) -> CGImage? {
        if let cached = images[id] { return cached }
        guard let source = CGImageSourceCreateWithURL(imageURL(id) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[id] = image
        return image
    }

    // MARK: - Editing

    /// Saves a picture as a new charm. Its weight follows how much of the square it fills.
    @discardableResult
    func addCustom(image: CGImage, name: String) throws -> String {
        let id = UUID().uuidString
        guard let destination = CGImageDestinationCreateWithURL(imageURL(id) as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }

        let aspect = Double(image.width) / Double(max(1, image.height))
        let record = CustomCharmRecord(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Charm" : name,
            created: Date(),
            mass: 3 + min(2, aspect),
            sizeScale: 1.1
        )
        images[id] = image
        customCharms.append(record)
        save()
        CharmArtwork.clearCache()
        return record.charmID
    }

    func deleteCustom(_ charmID: String) {
        let raw = String(charmID.dropFirst(Self.customPrefix.count))
        customCharms.removeAll { $0.id == raw }
        images[raw] = nil
        try? FileManager.default.removeItem(at: imageURL(raw))
        save()
    }

    func renameCustom(_ charmID: String, to name: String) {
        let raw = String(charmID.dropFirst(Self.customPrefix.count))
        guard let index = customCharms.firstIndex(where: { $0.id == raw }) else { return }
        customCharms[index].name = name
        save()
    }
}
