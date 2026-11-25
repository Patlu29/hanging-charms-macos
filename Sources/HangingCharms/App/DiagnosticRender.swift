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
        if let flag = arguments.firstIndex(of: "--check-pages"), flag + 1 < arguments.count {
            checkPages(into: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
            return true
        }
        if let flag = arguments.firstIndex(of: "--render-hooks"), flag + 1 < arguments.count {
            renderHooks(to: URL(fileURLWithPath: arguments[flag + 1]))
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
        print("Rendered \(charms.count - failures.count) of \(charms.count) charms in \(CharmCollection.allCases.count) collections to \(url.path)")
        if !CharmArtwork.missingSymbols.isEmpty {
            print("Missing SF Symbols on this Mac: \(CharmArtwork.missingSymbols.sorted().joined(separator: ", "))")
            exit(1)
        }
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
            settings.hookStyle = .lobsterClasp
            settings.hookFinish = .silver
            settings.hookSize = 1.3
            settings.grappleStyle = .grapplingHook
            settings.grappleFinish = .silver
            settings.grappleSize = 1.4
            settings.beads = .few
            settings.beadColor = RGBA(hex: 0x2F6FDE)
            settings.linkSize = 1.6
        }
        let size = CGSize(width: 700, height: 760)
        let library = CharmLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("hc-diag-\(UUID().uuidString)"))
        let charms = ["evil-eye", "clover", "heart"].compactMap { library.resolve($0) }
        let configuration = RopeConfiguration.make(unit: 300, style: style)
        let metrics = charms.map { charm in
            let scale = settings.scale(for: charm.id)
            return CharmMetrics(mass: charm.metrics.mass * scale, sizeScale: charm.metrics.sizeScale * scale)
        }
        let rope = RopeSimulation(configuration: configuration, anchor: CGPoint(x: size.width / 2, y: 40),
                                  charms: metrics, massScale: style.physics.charmMassScale, startAngle: 0.5)
        for _ in 0..<18 { rope.step(deltaTime: 1 / 60) }

        let renderer = RopeRenderer()
        renderer.root.frame = CGRect(origin: .zero, size: size)
        renderer.setCanvas(height: size.height, scale: 2)
        renderer.configure(look: settings.resolvedRopeAppearance, unit: configuration.charmUnit,
                           ropeGlow: settings.ropeGlow, linkSize: settings.linkSize)
        let grappleSide = CGFloat(configuration.charmUnit * 0.12 * settings.grappleSize)
        let grapplePalette = settings.grappleFinish.palette(rope: settings.resolvedRopeAppearance)
        renderer.setGrapple(AttachmentArtwork.grappleImage(settings.grappleStyle, base: grapplePalette.base, highlight: grapplePalette.highlight,
                                                           shadow: grapplePalette.shadow, pixels: Int(grappleSide * 2)),
                            side: grappleSide, eyeY: AttachmentArtwork.eyeY(for: settings.grappleStyle))
        renderer.setBeads(spacing: settings.beads.spacingFraction.map { CGFloat(configuration.charmUnit * $0) }, color: settings.beadColor,
                          diameter: CGFloat(max(0.5, configuration.charmUnit * settings.resolvedRopeAppearance.widthScale) * settings.beadSize))
        let diameters = rope.layout.slots.map { CGFloat($0.radius * 2) }
        let connector = Connector.from(settings)
        renderer.setCharms(zip(charms, diameters).map { CharmArtwork.image(for: $0, diameter: $1, scale: 2, shadow: settings.charmShadow, connector: connector) }, diameters: diameters)
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

    /// Every hook on several charm shapes, and every grapple in every finish.
    private static func renderHooks(to url: URL) {
        let library = CharmLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("hc-diag-\(UUID().uuidString)"))
        let charms = ["evil-eye", "hamsa", "tortoise", "heart", "crescent", "plane"].compactMap { library.resolve($0) }
        let finishes: [AttachmentFinish] = [.matchRope, .gold, .silver, .roseGold, .bronze, .black]
        let cell: CGFloat = 130, scale: CGFloat = 2
        let columns = max(charms.count, finishes.count)
        let rows = HookStyle.allCases.count + GrappleStyle.allCases.count
        let width = Int(cell * CGFloat(columns + 1) * scale), height = Int(cell * CGFloat(rows) * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        ctx.setFillColor(CGColor(srgbRed: 0.82, green: 0.85, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func label(_ text: String, row: Int) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 12 * scale, weight: .semibold), .foregroundColor: NSColor.black,
            ]))
            ctx.textPosition = CGPoint(x: 8 * scale, y: (CGFloat(rows - 1 - row) + 0.45) * cell * scale)
            CTLineDraw(line, ctx)
        }
        var failures: [String] = []
        var rope = AppSettings()
        rope.ropeStyle = .goldChain
        for (row, style) in HookStyle.allCases.enumerated() {
            label(style.displayName, row: row)
            rope.hookStyle = style
            rope.hookFinish = finishes[row % finishes.count]
            let connector = Connector.from(rope)
            for (column, charm) in charms.enumerated() {
                let side = cell * 0.9 * scale
                guard let image = CharmArtwork.image(for: charm, diameter: cell * 0.9, scale: scale, connector: connector) else {
                    failures.append("\(style.rawValue)/\(charm.id)")
                    continue
                }
                let origin = CGPoint(x: CGFloat(column + 1) * cell * scale, y: CGFloat(rows - 1 - row) * cell * scale)
                ctx.draw(image, in: CGRect(x: origin.x + (cell * scale - side) / 2, y: origin.y + (cell * scale - side) / 2, width: side, height: side))
            }
        }
        for (index, style) in GrappleStyle.allCases.enumerated() {
            let row = HookStyle.allCases.count + index
            label(style.displayName, row: row)
            for (column, finish) in finishes.enumerated() {
                let palette = finish.palette(rope: RopeStyle.goldChain.appearance)
                let image = AttachmentArtwork.grappleImage(style, base: palette.base, highlight: palette.highlight,
                                                           shadow: palette.shadow, pixels: Int(cell * 0.6 * scale))
                if image == nil, style != .none { failures.append("grapple \(style.rawValue)") }
                guard let image else { continue }
                let side = cell * 0.6 * scale
                let origin = CGPoint(x: CGFloat(column + 1) * cell * scale, y: CGFloat(rows - 1 - row) * cell * scale)
                ctx.draw(image, in: CGRect(x: origin.x + (cell * scale - side) / 2, y: origin.y + (cell * scale - side) / 2, width: side, height: side))
            }
        }
        if let image = ctx.makeImage() { writePNG(image, to: url) }
        if !failures.isEmpty {
            print("Failed: \(failures.joined(separator: ", "))")
            exit(1)
        }
    }

    /// Renders every Customize page and Appearance tab, and fails if any comes out blank.
    /// A SwiftUI layout that cannot be resolved draws nothing at all and reports nothing,
    /// which is how the Create page once shipped empty.
    private static func checkPages(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var blank: [String] = []
        var targets: [(CustomizePage, AppearanceTab?)] = CustomizePage.allCases.filter { $0 != .appearance }.map { ($0, nil) }
        targets += AppearanceTab.allCases.map { (.appearance, $0) }
        for (page, tab) in targets {
            let name = tab.map { "appearance-\($0.rawValue)" } ?? page.rawValue
            if let tab { AppearanceView.startTab = tab }
            let url = folder.appendingPathComponent("\(name).png")
            guard let image = renderCustomize(page: page, to: url) else {
                blank.append(name)
                continue
            }
            let colours = distinctColours(in: image, from: 0.25)
            print("\(colours > 40 ? "ok   " : "BLANK") \(name) (\(colours) colours)")
            if colours <= 40 { blank.append(name) }
        }
        if !blank.isEmpty {
            print("Blank pages: \(blank.joined(separator: ", "))")
            exit(1)
        }
    }

    /// Distinct colours in the image to the right of `from` (a fraction of the width),
    /// which skips the sidebar so a blank page cannot pass on its labels.
    private static func distinctColours(in image: CGImage, from: Double) -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        var seen = Set<UInt32>()
        let start = Int(Double(width) * from)
        for y in stride(from: 0, to: height, by: 3) {
            for x in stride(from: start, to: width, by: 3) {
                let i = (y * width + x) * 4
                seen.insert(UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2]))
                if seen.count > 400 { return seen.count }
            }
        }
        return seen.count
    }

    /// A Customize page, drawn offscreen.
    @discardableResult
    private static func renderCustomize(page: CustomizePage, to url: URL) -> CGImage? {
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
        // On screen, as the real Customize window is: some pages (Create) do not draw
        // at all in a window that has never been shown.
        NSApplication.shared.setActivationPolicy(.accessory)
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        // Some pages lay out over a few run loop turns; give them time, twice.
        for _ in 0..<3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            hosting.layoutSubtreeIfNeeded()
        }
        if ProcessInfo.processInfo.environment["HC_DEBUG_RENDER"] != nil {
            print("hosting bounds \(hosting.bounds), fitting \(hosting.fittingSize), window \(window.frame.size)")
        }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let image = rep.cgImage { writePNG(image, to: url) }
        window.orderOut(nil)
        return rep.cgImage
    }
}
