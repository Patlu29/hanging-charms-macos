import AppKit
import CoreText
import HangingCharmsCore

/// Draws every charm at run time. Nothing here is a bitmap asset: built-in charms are
/// SF Symbols or vector paths given a metal or enamel finish, and custom charms are the
/// user's own pictures given a ring.
///
/// All drawing is in a y-up square of side `D`. The ring sits at the top centre; the
/// overlay hangs the image from ``ringAnchorY``.
@MainActor
enum CharmArtwork {
    /// Where the rope ties on, as a fraction of the image height from the bottom.
    static let ringAnchorY: CGFloat = 0.975

    /// The body area under the ring, in unit coordinates.
    static let bodyBox = CGRect(x: 0.08, y: 0.04, width: 0.84, height: 0.80)

    private static var cache: [String: CGImage] = [:]
    /// Whether the charm currently being drawn casts a drop shadow.
    private static var drawsShadow = true

    /// The hook every charm is drawn with unless one is passed in. Set from settings.
    static var connector = Connector.default
    private static var activeConnector = Connector.default
    /// Where the body of the charm being drawn starts, recorded by ``drawBail(_:to:finish:)``.
    private static var bodyTop: CGFloat = 0.84

    static func clearCache() { cache.removeAll() }

    // MARK: - Entry points

    static func image(for charm: ResolvedCharm, diameter: CGFloat, scale: CGFloat, shadow: Bool = true,
                      connector: Connector? = nil) -> CGImage? {
        let pixels = Int((diameter * scale).rounded())
        guard pixels > 4 else { return nil }
        let hook = connector ?? Self.connector
        let key = "\(charm.id)@\(pixels)\(shadow ? "" : "-flat")#\(hook.key)"
        activeConnector = hook
        drawsShadow = shadow
        defer { drawsShadow = true }
        if let cached = cache[key] { return cached }
        let image: CGImage?
        switch charm.source {
        case let .builtIn(definition): image = render(art: definition.art, pixels: pixels)
        case let .custom(picture): image = render(picture: picture, pixels: pixels)
        }
        if let image {
            if cache.count > 160 { cache.removeAll() }
            cache[key] = image
        }
        return image
    }

    static func nsImage(for charm: ResolvedCharm, side: CGFloat) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cg = image(for: charm, diameter: side, scale: scale) else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }

    // MARK: - Rendering

    private static func makeContext(pixels: Int) -> CGContext? {
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.interpolationQuality = .high
        context?.setAllowsAntialiasing(true)
        context?.setShouldAntialias(true)
        return context
    }

    private static func render(art: CharmArt, pixels: Int) -> CGImage? {
        guard let ctx = makeContext(pixels: pixels) else { return nil }
        let d = CGFloat(pixels)
        ctx.scaleBy(x: d, y: d) // unit space from here

        bodyTop = bodyBox.maxY
        withCharmShadow(ctx, d: d) {
            switch art {
            case let .cutout(symbol, finish):
                let ring = ringFinish(for: finish)
                drawRing(ctx, finish: ring)
                if let mask = symbolMask(symbol, pixels: pixels) {
                    let rect = fit(mask, in: bodyBox)
                    drawBail(ctx, to: inkTop(of: mask, in: rect), finish: ring)
                    drawMetal(ctx, mask: mask, rect: rect, finish: finish, depth: 1)
                } else {
                    drawMedallion(ctx, symbol: nil, rim: finish, face: finish, pixels: pixels)
                }
            case let .medallion(symbol, finish, face):
                drawRing(ctx, finish: ringFinish(for: finish))
                drawMedallion(ctx, symbol: symbol, rim: finish, face: face, pixels: pixels)
            case let .drawn(shape):
                DrawnCharms.draw(shape, in: ctx, pixels: pixels)
            }
            AttachmentArtwork.drawConnector(ctx, activeConnector, top: ringAnchorY, bodyTop: bodyTop)
        }
        return ctx.makeImage()
    }

    private static func render(picture: CGImage, pixels: Int) -> CGImage? {
        guard let ctx = makeContext(pixels: pixels) else { return nil }
        let d = CGFloat(pixels)
        ctx.scaleBy(x: d, y: d)
        withCharmShadow(ctx, d: d) {
            let rect = fit(picture, in: bodyBox)
            ctx.draw(picture, in: rect)
            AttachmentArtwork.drawConnector(ctx, activeConnector, top: ringAnchorY, bodyTop: inkTop(of: picture, in: rect))
        }
        return ctx.makeImage()
    }

    // MARK: - Building blocks (unit space)

    static func withCharmShadow(_ ctx: CGContext, d: CGFloat, _ body: () -> Void) {
        ctx.saveGState()
        if drawsShadow {
            ctx.setShadow(
                offset: CGSize(width: 0, height: -0.018 * d),
                blur: 0.045 * d,
                color: CGColor(gray: 0, alpha: 0.38)
            )
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    static func ringFinish(for finish: CharmFinish) -> CharmFinish {
        switch finish {
        case .gold, .silver, .roseGold, .bronze: finish
        case .pearl, .obsidian: .silver
        default: .gold
        }
    }

    /// Charms no longer carry a ring of their own: the chosen ``Connector`` is drawn
    /// after the body instead. Kept so the drawing code reads as before.
    static func drawRing(_ ctx: CGContext, finish: CharmFinish) {}

    /// Records where the charm's body starts, which is where the connector reaches down to.
    static func drawBail(_ ctx: CGContext, to top: CGFloat, finish: CharmFinish) {
        bodyTop = min(top, ringAnchorY - 0.04)
    }

    static func drawMedallion(_ ctx: CGContext, symbol: String?, rim: CharmFinish, face: CharmFinish, pixels: Int) {
        let centre = CGPoint(x: 0.5, y: 0.45)
        let outer: CGFloat = 0.38, inner: CGFloat = 0.31
        drawBail(ctx, to: centre.y + outer, finish: ringFinish(for: rim))
        // Rim.
        fillDisc(ctx, centre: centre, radius: outer + 0.006, color: rim.shadow)
        ctx.saveGState()
        ctx.addEllipse(in: disc(centre, outer))
        ctx.clip()
        linearGradient(ctx, from: CGPoint(x: 0.3, y: centre.y + outer), to: CGPoint(x: 0.7, y: centre.y - outer),
                       colors: [rim.highlight, rim.base, rim.shadow, rim.base])
        ctx.restoreGState()
        // Face.
        ctx.saveGState()
        ctx.addEllipse(in: disc(centre, inner))
        ctx.clip()
        linearGradient(ctx, from: CGPoint(x: 0.5, y: centre.y - inner), to: CGPoint(x: 0.5, y: centre.y + inner),
                       colors: [face.highlight, face.base, face.shadow])
        ctx.restoreGState()
        // Symbol, embossed in the rim's metal.
        if let symbol, let mask = symbolMask(symbol, pixels: pixels) {
            let box = disc(centre, inner * 0.66)
            drawMetal(ctx, mask: mask, rect: fit(mask, in: box), finish: rim, depth: 0.6)
        }
        sheen(ctx, in: disc(centre, outer))
    }

    /// Fills an alpha mask with a bevelled metal or enamel finish.
    static func drawMetal(_ ctx: CGContext, mask: CGImage, rect: CGRect, finish: CharmFinish, depth: CGFloat) {
        // Depth: a darker copy below and to the right reads as thickness.
        tint(ctx, mask: mask, rect: rect.offsetBy(dx: 0.010 * depth, dy: -0.016 * depth), color: finish.shadow)
        // Rim light: a lighter copy up and to the left.
        tint(ctx, mask: mask, rect: rect.offsetBy(dx: -0.004 * depth, dy: 0.006 * depth), color: finish.highlight)
        // Body.
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.draw(mask, in: rect)
        ctx.setBlendMode(.sourceIn)
        linearGradient(ctx, from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.minY),
                       colors: [finish.highlight, finish.base, finish.shadow, finish.base])
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        // Sheen, clipped to the shape.
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.draw(mask, in: rect)
        ctx.setBlendMode(.sourceIn)
        radialGradient(ctx, centre: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.78),
                       radius: max(rect.width, rect.height) * 0.55,
                       colors: [RGBA(1, 1, 1, 0.55), RGBA(1, 1, 1, 0)])
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    static func tint(_ ctx: CGContext, mask: CGImage, rect: CGRect, color: RGBA) {
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.draw(mask, in: rect)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(color.cg)
        ctx.fill(rect.insetBy(dx: -0.05, dy: -0.05))
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    static func sheen(_ ctx: CGContext, in rect: CGRect) {
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        radialGradient(ctx, centre: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.74),
                       radius: rect.width * 0.5, colors: [RGBA(1, 1, 1, 0.45), RGBA(1, 1, 1, 0)])
        ctx.restoreGState()
    }

    // MARK: - Symbols

    private static var symbolCache: [String: CGImage] = [:]

    /// The symbol as a black alpha mask, rendered large and trimmed to its ink.
    static func symbolMask(_ name: String, pixels: Int) -> CGImage? {
        let size = max(64, pixels)
        let key = "\(name)#\(size)"
        if let cached = symbolCache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(size), weight: .bold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        var proposed = CGRect(origin: .zero, size: symbol.size)
        guard let cg = symbol.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        let trimmed = AlphaTrim.trim(cg) ?? cg
        symbolCache[key] = trimmed
        return trimmed
    }

    // MARK: - Geometry helpers

    /// Where the first opaque pixel is in the image's centre column, in unit space once
    /// the image is drawn in `rect`. A wide shape (a tortoise, an aeroplane) has no ink
    /// at the top of its box under the ring, so the link has to reach further down.
    static func inkTop(of image: CGImage, in rect: CGRect) -> CGFloat {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return rect.maxY }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return rect.maxY }
        let band = max(1, width / 40)
        let columns = max(0, width / 2 - band)...min(width - 1, width / 2 + band)
        for row in 0..<height {
            let base = row * width * 4
            if columns.contains(where: { pixels[base + $0 * 4 + 3] > 96 }) {
                // Memory rows run top-down.
                return rect.maxY - rect.height * CGFloat(row) / CGFloat(height)
            }
        }
        // Nothing in the centre (a hollow shape): stop at the box top.
        return rect.maxY
    }

    /// The largest rect with the image's aspect that fits `box`, centred horizontally
    /// and pushed to the top so the charm hangs right under its ring.
    static func fit(_ image: CGImage, in box: CGRect) -> CGRect {
        let aspect = CGFloat(image.width) / CGFloat(max(1, image.height))
        var width = box.width, height = box.width / aspect
        if height > box.height {
            height = box.height
            width = height * aspect
        }
        return CGRect(x: box.midX - width / 2, y: box.maxY - height, width: width, height: height)
    }

    static func disc(_ centre: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }

    static func fillDisc(_ ctx: CGContext, centre: CGPoint, radius: CGFloat, color: RGBA) {
        ctx.setFillColor(color.cg)
        ctx.fillEllipse(in: disc(centre, radius))
    }

    static func linearGradient(_ ctx: CGContext, from: CGPoint, to: CGPoint, colors: [RGBA]) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors.map(\.cg) as CFArray, locations: nil) else { return }
        ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    static func radialGradient(_ ctx: CGContext, centre: CGPoint, radius: CGFloat, colors: [RGBA]) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors.map(\.cg) as CFArray, locations: nil) else { return }
        ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [.drawsAfterEndLocation])
    }
}

extension RGBA {
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// Crops an image to the bounding box of its non-transparent pixels.
enum AlphaTrim {
    static func trim(_ image: CGImage, threshold: UInt8 = 8) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where pixels[row + x * 4 + 3] > threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Bitmap rows run top-down in memory, which is the same order cropping uses.
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
