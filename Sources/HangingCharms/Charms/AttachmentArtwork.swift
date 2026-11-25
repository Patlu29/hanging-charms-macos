import AppKit
import HangingCharmsCore

/// The connector drawn into every charm image, between the rope's end and the charm.
struct Connector: Equatable {
    var style: HookStyle
    var base: RGBA
    var highlight: RGBA
    var shadow: RGBA
    var size: Double

    static func from(_ settings: AppSettings) -> Connector {
        let palette = settings.hookFinish.palette(rope: settings.resolvedRopeAppearance)
        return Connector(style: settings.hookStyle, base: palette.base, highlight: palette.highlight,
                         shadow: palette.shadow, size: settings.hookSize)
    }

    static let `default` = Connector.from(AppSettings())

    /// Part of every cache key, so a new hook redraws every charm.
    var key: String {
        func hex(_ c: RGBA) -> String { String(format: "%02x%02x%02x", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255)) }
        return "\(style.rawValue)-\(hex(base))\(hex(shadow))-\(Int(size * 100))"
    }
}

/// Hooks and grapples, drawn in a y-up unit square.
@MainActor
enum AttachmentArtwork {
    // MARK: - Metal strokes

    /// Strokes the current path as round wire: a shadow edge, the metal, a highlight.
    static func strokeWire(_ ctx: CGContext, _ path: CGPath, width: CGFloat, base: RGBA, highlight: RGBA, shadow: RGBA) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.setLineWidth(width)
        ctx.setStrokeColor(shadow.cg)
        ctx.translateBy(x: width * 0.12, y: -width * 0.18)
        ctx.strokePath()
        ctx.translateBy(x: -width * 0.12, y: width * 0.18)
        ctx.addPath(path)
        ctx.setLineWidth(width * 0.86)
        ctx.setStrokeColor(base.cg)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setLineWidth(width * 0.3)
        ctx.setStrokeColor(highlight.cg.copy(alpha: 0.85)!)
        ctx.translateBy(x: -width * 0.1, y: width * 0.12)
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func fillMetal(_ ctx: CGContext, _ path: CGPath, base: RGBA, highlight: RGBA, shadow: RGBA) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let box = path.boundingBox
        CharmArtwork.linearGradient(ctx, from: CGPoint(x: box.minX, y: box.maxY), to: CGPoint(x: box.maxX, y: box.minY),
                                    colors: [highlight, base, shadow])
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(max(box.width, box.height) * 0.04)
        ctx.setStrokeColor(shadow.cg)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Charm connectors

    /// Draws `connector` from the rope's end at `top` down to the charm body at `bodyTop`.
    static func drawConnector(_ ctx: CGContext, _ connector: Connector, top: CGFloat, bodyTop: CGFloat) {
        let s = CGFloat(connector.size)
        let x: CGFloat = 0.5
        let room = max(0.04, top - bodyTop)
        let base = connector.base, light = connector.highlight, dark = connector.shadow
        let wire = 0.022 * s

        /// A straight link from the connector's lowest point into the charm.
        func bail(from y: CGFloat, x fromX: CGFloat = x) {
            guard y > bodyTop else { return }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: fromX, y: y))
            path.addLine(to: CGPoint(x: x, y: bodyTop - 0.006))
            strokeWire(ctx, path, width: 0.016 * s, base: base, highlight: light, shadow: dark)
        }

        switch connector.style {
        case .knot:
            // The cord itself carries on into the charm, with a knot where it is tied.
            let cord = CGMutablePath()
            cord.move(to: CGPoint(x: x, y: top))
            cord.addLine(to: CGPoint(x: x, y: bodyTop - 0.01))
            strokeWire(ctx, cord, width: 0.02 * min(s, 1.4), base: base, highlight: light, shadow: dark)
            let knotY = bodyTop + min(room * 0.45, 0.05 * s)
            let knot = CGPath(ellipseIn: CGRect(x: x - 0.03 * s, y: knotY - 0.022 * s, width: 0.06 * s, height: 0.044 * s), transform: nil)
            fillMetal(ctx, knot, base: base, highlight: light, shadow: dark)
            let wrap = CGMutablePath()
            wrap.move(to: CGPoint(x: x - 0.026 * s, y: knotY + 0.006 * s))
            wrap.addQuadCurve(to: CGPoint(x: x + 0.026 * s, y: knotY - 0.006 * s), control: CGPoint(x: x, y: knotY + 0.02 * s))
            ctx.saveGState()
            ctx.addPath(wrap)
            ctx.setLineWidth(0.006 * s)
            ctx.setStrokeColor(dark.cg)
            ctx.strokePath()
            ctx.restoreGState()

        case .jumpRing:
            let r = 0.048 * s
            let ring = CGPath(ellipseIn: CGRect(x: x - r, y: top - 2 * r, width: 2 * r, height: 2 * r), transform: nil)
            strokeWire(ctx, ring, width: wire, base: base, highlight: light, shadow: dark)
            bail(from: top - 2 * r)

        case .sHook:
            let r = min(0.04 * s, room / 4.4)
            let upper = CGPoint(x: x, y: top - r)
            let lower = CGPoint(x: x, y: top - 3 * r)
            let path = CGMutablePath()
            path.addArc(center: upper, radius: r, startAngle: -.pi / 6, endAngle: .pi * 1.5, clockwise: false)
            path.addArc(center: lower, radius: r, startAngle: .pi / 2, endAngle: -.pi * 5 / 6, clockwise: true)
            strokeWire(ctx, path, width: wire * 0.9, base: base, highlight: light, shadow: dark)
            bail(from: top - 4 * r)

        case .fishHook:
            let shankBottom = top - min(0.1 * s, room * 0.7)
            let r = 0.035 * s
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: top - 0.012 * s))
            path.addLine(to: CGPoint(x: x, y: shankBottom))
            path.addArc(center: CGPoint(x: x + r, y: shankBottom), radius: r, startAngle: .pi, endAngle: .pi * 2.25, clockwise: false)
            strokeWire(ctx, path, width: wire * 0.85, base: base, highlight: light, shadow: dark)
            // The eye the rope is tied through, and the barb.
            let eye = CGPath(ellipseIn: CGRect(x: x - 0.013 * s, y: top - 0.026 * s, width: 0.026 * s, height: 0.026 * s), transform: nil)
            strokeWire(ctx, eye, width: 0.008 * s, base: base, highlight: light, shadow: dark)
            let tip = CGPoint(x: x + r + r * cos(.pi * 0.25), y: shankBottom + r * sin(.pi * 0.25))
            let barb = CGMutablePath()
            barb.move(to: tip)
            barb.addLine(to: CGPoint(x: tip.x - 0.016 * s, y: tip.y - 0.004 * s))
            barb.addLine(to: CGPoint(x: tip.x - 0.004 * s, y: tip.y - 0.016 * s))
            barb.closeSubpath()
            fillMetal(ctx, barb, base: base, highlight: light, shadow: dark)
            bail(from: shankBottom - r, x: x + r)

        case .lobsterClasp:
            let height = min(0.11 * s, room * 0.75)
            let width = 0.06 * s
            let topRing = 0.014 * s
            let ring = CGPath(ellipseIn: CGRect(x: x - topRing, y: top - 2 * topRing, width: 2 * topRing, height: 2 * topRing), transform: nil)
            strokeWire(ctx, ring, width: 0.008 * s, base: base, highlight: light, shadow: dark)
            let bodyTopY = top - 2 * topRing
            let body = CGMutablePath()
            body.move(to: CGPoint(x: x, y: bodyTopY))
            body.addCurve(to: CGPoint(x: x, y: bodyTopY - height),
                          control1: CGPoint(x: x + width * 0.95, y: bodyTopY - height * 0.1),
                          control2: CGPoint(x: x + width * 0.6, y: bodyTopY - height))
            body.addCurve(to: CGPoint(x: x, y: bodyTopY),
                          control1: CGPoint(x: x - width * 0.6, y: bodyTopY - height),
                          control2: CGPoint(x: x - width * 0.95, y: bodyTopY - height * 0.1))
            body.closeSubpath()
            fillMetal(ctx, body, base: base, highlight: light, shadow: dark)
            // The spring gate.
            let gate = CGMutablePath()
            gate.move(to: CGPoint(x: x - width * 0.18, y: bodyTopY - height * 0.22))
            gate.addQuadCurve(to: CGPoint(x: x - width * 0.12, y: bodyTopY - height * 0.82),
                              control: CGPoint(x: x - width * 0.4, y: bodyTopY - height * 0.5))
            ctx.saveGState()
            ctx.addPath(gate)
            ctx.setLineWidth(0.006 * s)
            ctx.setStrokeColor(dark.cg)
            ctx.strokePath()
            ctx.restoreGState()
            bail(from: bodyTopY - height)

        case .carabiner:
            let height = min(0.12 * s, room * 0.8)
            let width = 0.065 * s
            let rect = CGRect(x: x - width / 2, y: top - height, width: width, height: height)
            let loop = CGPath(roundedRect: rect, cornerWidth: width * 0.48, cornerHeight: width * 0.48, transform: nil)
            strokeWire(ctx, loop, width: wire * 0.85, base: base, highlight: light, shadow: dark)
            // The gate: a lighter bar down one side.
            let gate = CGMutablePath()
            gate.move(to: CGPoint(x: rect.maxX, y: rect.maxY - width * 0.45))
            gate.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + width * 0.45))
            ctx.saveGState()
            ctx.addPath(gate)
            ctx.setLineWidth(wire * 0.5)
            ctx.setStrokeColor(light.cg)
            ctx.strokePath()
            ctx.restoreGState()
            bail(from: rect.minY)
        }
    }

    /// A close-up of a connector for the picker, five times its size on a charm.
    static func connectorPreview(_ connector: Connector, pixels: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let d = CGFloat(pixels)
        ctx.scaleBy(x: d, y: d)
        ctx.scaleBy(x: 4.4, y: 4.4)
        ctx.translateBy(x: -0.386, y: -0.77)
        ctx.setShadow(offset: CGSize(width: 0, height: -0.002), blur: 0.004, color: CGColor(gray: 0, alpha: 0.3))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        // A sliver of charm for the hook to hold.
        ctx.setFillColor(CGColor(gray: 0.55, alpha: 0.35))
        ctx.fillEllipse(in: CGRect(x: 0.42, y: 0.74, width: 0.16, height: 0.07))
        drawConnector(ctx, connector, top: 0.975, bodyTop: 0.8)
        ctx.endTransparencyLayer()
        return ctx.makeImage()
    }

    // MARK: - Grapples

    /// Where the rope is tied on each grapple, as a fraction of its height from the bottom.
    static func eyeY(for style: GrappleStyle) -> CGFloat {
        switch style {
        case .pin: 0.5
        case .grapplingHook: 0.12
        case .nail: 0.34
        case .binderClip: 0.1
        case .suctionCup: 0.14
        case .none: 0.5
        }
    }

    static func grappleImage(_ style: GrappleStyle, base: RGBA, highlight: RGBA, shadow: RGBA, pixels: Int) -> CGImage? {
        guard style != .none, pixels > 4,
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let d = CGFloat(pixels)
        ctx.scaleBy(x: d, y: d)
        ctx.setShadow(offset: CGSize(width: 0, height: -0.03 * d), blur: 0.06 * d, color: CGColor(gray: 0, alpha: 0.4))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let wire: CGFloat = 0.07

        switch style {
        case .pin:
            let head = CGPath(ellipseIn: CharmArtwork.disc(CGPoint(x: 0.5, y: 0.5), 0.2), transform: nil)
            fillMetal(ctx, head, base: base, highlight: highlight, shadow: shadow)
            CharmArtwork.sheen(ctx, in: CharmArtwork.disc(CGPoint(x: 0.5, y: 0.5), 0.2))

        case .grapplingHook:
            let crown = CGPoint(x: 0.5, y: 0.7)
            let shank = CGMutablePath()
            shank.move(to: CGPoint(x: 0.5, y: 0.2))
            shank.addLine(to: CGPoint(x: 0.5, y: crown.y + 0.04))
            strokeWire(ctx, shank, width: wire, base: base, highlight: highlight, shadow: shadow)
            // Two prongs out to the sides, curling back down over the edge, and one
            // pointing at you, drawn short.
            for side in [-1.0, 1.0] as [CGFloat] {
                let prong = CGMutablePath()
                prong.move(to: crown)
                prong.addCurve(to: CGPoint(x: 0.5 + side * 0.32, y: 0.62),
                               control1: CGPoint(x: 0.5 + side * 0.12, y: 0.98),
                               control2: CGPoint(x: 0.5 + side * 0.36, y: 0.92))
                strokeWire(ctx, prong, width: wire * 0.85, base: base, highlight: highlight, shadow: shadow)
                let tip = CGMutablePath()
                tip.move(to: CGPoint(x: 0.5 + side * 0.32, y: 0.55))
                tip.addLine(to: CGPoint(x: 0.5 + side * 0.36, y: 0.66))
                tip.addLine(to: CGPoint(x: 0.5 + side * 0.27, y: 0.65))
                tip.closeSubpath()
                fillMetal(ctx, tip, base: base, highlight: highlight, shadow: shadow)
            }
            let front = CGPath(ellipseIn: CharmArtwork.disc(crown, 0.06), transform: nil)
            fillMetal(ctx, front, base: base, highlight: highlight, shadow: shadow)
            let eye = CGPath(ellipseIn: CharmArtwork.disc(CGPoint(x: 0.5, y: 0.12), 0.07), transform: nil)
            strokeWire(ctx, eye, width: wire * 0.6, base: base, highlight: highlight, shadow: shadow)

        case .nail:
            let shank = CGMutablePath()
            shank.move(to: CGPoint(x: 0.5, y: 0.6))
            shank.addLine(to: CGPoint(x: 0.5, y: 0.3))
            strokeWire(ctx, shank, width: wire * 0.9, base: base, highlight: highlight, shadow: shadow)
            let head = CGPath(ellipseIn: CGRect(x: 0.28, y: 0.56, width: 0.44, height: 0.2), transform: nil)
            fillMetal(ctx, head, base: base, highlight: highlight, shadow: shadow)

        case .binderClip:
            let body = CGMutablePath()
            body.move(to: CGPoint(x: 0.2, y: 0.95))
            body.addLine(to: CGPoint(x: 0.8, y: 0.95))
            body.addLine(to: CGPoint(x: 0.86, y: 0.6))
            body.addLine(to: CGPoint(x: 0.14, y: 0.6))
            body.closeSubpath()
            fillMetal(ctx, body, base: base, highlight: highlight, shadow: shadow)
            let handles = CGMutablePath()
            handles.move(to: CGPoint(x: 0.24, y: 0.64))
            handles.addLine(to: CGPoint(x: 0.44, y: 0.14))
            handles.addLine(to: CGPoint(x: 0.56, y: 0.14))
            handles.addLine(to: CGPoint(x: 0.76, y: 0.64))
            strokeWire(ctx, handles, width: wire * 0.5, base: CharmFinish.silver.base,
                       highlight: CharmFinish.silver.highlight, shadow: CharmFinish.silver.shadow)

        case .suctionCup:
            let stem = CGMutablePath()
            stem.move(to: CGPoint(x: 0.5, y: 0.62))
            stem.addLine(to: CGPoint(x: 0.5, y: 0.22))
            strokeWire(ctx, stem, width: wire, base: base, highlight: highlight, shadow: shadow)
            let cup = CGMutablePath()
            cup.move(to: CGPoint(x: 0.12, y: 0.95))
            cup.addQuadCurve(to: CGPoint(x: 0.88, y: 0.95), control: CGPoint(x: 0.5, y: 0.4))
            cup.closeSubpath()
            ctx.saveGState()
            ctx.setAlpha(0.65)
            fillMetal(ctx, cup, base: base, highlight: highlight, shadow: shadow)
            ctx.restoreGState()
            let eye = CGPath(ellipseIn: CharmArtwork.disc(CGPoint(x: 0.5, y: 0.14), 0.07), transform: nil)
            strokeWire(ctx, eye, width: wire * 0.6, base: base, highlight: highlight, shadow: shadow)

        case .none:
            break
        }
        ctx.endTransparencyLayer()
        return ctx.makeImage()
    }
}
