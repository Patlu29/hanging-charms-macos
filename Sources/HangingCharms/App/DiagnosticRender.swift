import AppKit
import SwiftUI
import HangingCharmsCore

/// `HangingCharms --render-catalogue out.png` draws every built-in charm into a contact
/// sheet and exits. Used to review artwork and in CI to prove every charm renders.
@MainActor
enum DiagnosticRender {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render-scene"), flag + 1 < arguments.count {
            renderScene(to: URL(fileURLWithPath: arguments[flag + 1]),
                        style: arguments.dropFirst(flag + 2).first.flatMap(RopeStyle.init) ?? .goldChain,
                        customised: arguments.contains("--customised"))
            return true
        }
        if let flag = arguments.firstIndex(of: "--render-customize"), flag + 2 < arguments.count {
            if let tab = arguments.dropFirst(flag + 3).first.flatMap(AppearanceTab.init) { AppearanceView.startTab = tab }
            renderCustomize(page: CustomizePage(rawValue: arguments[flag + 1]) ?? .library, to: URL(fileURLWithPath: arguments[flag + 2]))
            return true
        }
        if let flag = arguments.firstIndex(of: "--import-picture"), flag + 2 < arguments.count {
            let input = URL(fileURLWithPath: arguments[flag + 1]), output = URL(fileURLWithPath: arguments[flag + 2])
            var done = false
            Task { @MainActor in
                do {
                    let picture = try PictureImporter.load(input)
                    let subject = await PictureImporter.cutOutSubject(picture)
                    print(subject == nil ? "No subject found; using whole picture" : "Subject cut out")
                    let finished = try PictureImporter.finish(subject ?? picture)
                    let charm = ResolvedCharm(id: "diag", name: "", detail: "", collectionName: "", metrics: .default, sound: .glass, source: .custom(finished))
                    if let image = CharmArtwork.image(for: charm, diameter: 240, scale: 2) { writePNG(image, to: output) }
                } catch {
                    print("Import failed: \(error.localizedDescription)")
                }
                done = true
            }
            while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            return true
        }
        guard let flag = arguments.firstIndex(of: "--render-catalogue"), flag + 1 < arguments.count else { return false }
        let url = URL(fileURLWithPath: arguments[flag + 1])
        let library = CharmLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("hc-diag-\(UUID().uuidString)"))
        let charms = CharmCatalog.all.compactMap { library.resolve($0.id) }
        let cell: CGFloat = 150, columns = 8
        let rows = Int((Double(charms.count) / Double(columns)).rounded(.up))
        let scale: CGFloat = 2
        let width = Int(cell * CGFloat(columns) * scale), height = Int(cell * CGFloat(rows) * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return true }
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.24, blue: 0.32, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var failures: [String] = []
        for (index, charm) in charms.enumerated() {
            let column = index % columns, row = index / columns
            let origin = CGPoint(x: CGFloat(column) * cell * scale, y: CGFloat(rows - 1 - row) * cell * scale)
            guard let image = CharmArtwork.image(for: charm, diameter: cell * 0.82, scale: scale) else {
                failures.append(charm.id)
                continue
            }
            let side = cell * 0.82 * scale
            ctx.draw(image, in: CGRect(x: origin.x + (cell * scale - side) / 2, y: origin.y + cell * scale * 0.14, width: side, height: side))
            let label = CTLineCreateWithAttributedString(NSAttributedString(string: charm.name, attributes: [
                .font: NSFont.systemFont(ofSize: 11 * scale, weight: .medium),
                .foregroundColor: NSColor.white,
            ]))
            let bounds = CTLineGetImageBounds(label, ctx)
            ctx.textPosition = CGPoint(x: origin.x + (cell * scale - bounds.width) / 2, y: origin.y + 6 * scale)
            CTLineDraw(label, ctx)
        }
        if let image = ctx.makeImage(),
           let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        print("Rendered \(charms.count - failures.count) of \(charms.count) charms to \(url.path)")
        if !failures.isEmpty {
            print("Failed: \(failures.joined(separator: ", "))")
            exit(1)
        }
        return true
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("Wrote \(url.path)")
    }

    /// Three charms mid-swing on a rope, through the real renderer.
    private static func renderScene(to url: URL, style: RopeStyle, customised: Bool) {
        // A sample of the customisation options: thick red and white chain with a glow
        // along it, a larger heart, no charm shadows and a wide teal glow.
        var settings = AppSettings()
        settings.ropeStyle = style
        if customised {
            settings.customRopeColors = true
            settings.ropePrimary = RGBA(hex: 0xE0303A)
            settings.ropeSecondary = RGBA(hex: 0xFFFFFF)
            settings.ropePattern = .chain
            settings.ropeThickness = 1.8
            settings.ropeGlow = true
            settings.charmShadow = false
            settings.setScale(1.5, for: "heart")
            settings.customGlowColor = true
            settings.glowColor = RGBA(hex: 0x3FE0C8)
            settings.glowSize = 1.6
        }
        let size = CGSize(width: 700, height: 760)
        let library = CharmLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("hc-diag-\(UUID().uuidString)"))
        let charms = ["evil-eye", "clover", "heart"].compactMap { library.resolve($0) }
        let configuration = RopeConfiguration.make(unit: 300, style: style)
        let metrics = charms.map { charm in
            let scale = settings.scale(for: charm.id)
            return CharmMetrics(mass: charm.metrics.mass * scale, sizeScale: charm.metrics.sizeScale * scale)
        }
        let rope = RopeSimulation(configuration: configuration, anchor: CGPoint(x: size.width / 2, y: 10),
                                  charms: metrics, massScale: style.physics.charmMassScale, startAngle: 0.5)
        for _ in 0..<18 { rope.step(deltaTime: 1 / 60) }

        let renderer = RopeRenderer()
        renderer.root.frame = CGRect(origin: .zero, size: size)
        renderer.setCanvas(height: size.height, scale: 2)
        renderer.configure(look: settings.resolvedRopeAppearance, unit: configuration.charmUnit,
                           showPin: settings.showPin, ropeGlow: settings.ropeGlow)
        let diameters = rope.layout.slots.map { CGFloat($0.radius * 2) }
        renderer.setCharms(zip(charms, diameters).map { CharmArtwork.image(for: $0, diameter: $1, scale: 2, shadow: settings.charmShadow) }, diameters: diameters)
        renderer.setGlow(enabled: true, color: settings.customGlowColor ? settings.glowColor : charms.last!.glowColor,
                         diameter: diameters.last!, intensity: settings.glowIntensity, size: settings.glowSize, breathing: false)
        renderer.render(rope)

        guard let ctx = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(srgbRed: 0.83, green: 0.86, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width * 2, height: size.height * 2))
        ctx.scaleBy(x: 2, y: 2)
        renderer.root.render(in: ctx)
        if let image = ctx.makeImage() { writePNG(image, to: url) }
        print(String(format: "stretch %.4f  sleeping %@", rope.maximumStretch, rope.isSleeping ? "yes" : "no"))
    }

    /// A Customize page, drawn offscreen.
    private static func renderCustomize(page: CustomizePage, to url: URL) {
        let defaults = UserDefaults(suiteName: "HangingCharms.diagnostic")!
        defaults.removePersistentDomain(forName: "HangingCharms.diagnostic")
        let store = SettingsStore(defaults: defaults)
        store.update { $0.charmIDs = ["evil-eye", "clover", "heart"]; $0.favourites = ["heart", "star"] }
        let library = CharmLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("hc-diag-\(UUID().uuidString)"))
        let model = CustomizeModel(store: store, library: library, audio: AudioService(), charmsChanged: {})
        model.page = page
        let size = NSSize(width: 920, height: 640)
        let hosting = NSHostingView(rootView: CustomizeView(model: model))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let image = rep.cgImage { writePNG(image, to: url) }
    }
}
