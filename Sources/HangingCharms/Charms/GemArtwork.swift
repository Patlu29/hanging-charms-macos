import AppKit
import HangingCharmsCore

/// Cut gemstones in a metal setting, drawn in the charm's y-up unit square.
@MainActor
enum GemArtwork {
    static func outline(_ cut: GemCut) -> CGPath {
        let centre = CGPoint(x: 0.5, y: 0.45)
        switch cut {
        case .round:
            return CGPath(ellipseIn: CharmArtwork.disc(centre, 0.3), transform: nil)
        case .oval, .cabochon, .opal:
            return CGPath(ellipseIn: CGRect(x: 0.25, y: 0.12, width: 0.5, height: 0.66), transform: nil)
        case .emerald:
            let rect = CGRect(x: 0.26, y: 0.12, width: 0.48, height: 0.66)
            let cut: CGFloat = 0.09
            let path = CGMutablePath()
            path.addLines(between: [
                CGPoint(x: rect.minX + cut, y: rect.minY), CGPoint(x: rect.maxX - cut, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + cut), CGPoint(x: rect.maxX, y: rect.maxY - cut),
                CGPoint(x: rect.maxX - cut, y: rect.maxY), CGPoint(x: rect.minX + cut, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY - cut), CGPoint(x: rect.minX, y: rect.minY + cut),
            ])
            path.closeSubpath()
            return path
        case .cushion:
            return CGPath(roundedRect: CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.6), cornerWidth: 0.17, cornerHeight: 0.17, transform: nil)
        case .heart:
            return DrawnCharms.heartPath(centre: CGPoint(x: 0.5, y: 0.5), size: 0.72)
        case .pear:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0.5, y: 0.8))
            path.addCurve(to: CGPoint(x: 0.5, y: 0.1), control1: CGPoint(x: 0.3, y: 0.62), control2: CGPoint(x: 0.08, y: 0.1))
            path.addCurve(to: CGPoint(x: 0.5, y: 0.8), control1: CGPoint(x: 0.92, y: 0.1), control2: CGPoint(x: 0.7, y: 0.62))
            path.closeSubpath()
            return path
        case .marquise:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0.5, y: 0.8))
            path.addQuadCurve(to: CGPoint(x: 0.5, y: 0.1), control: CGPoint(x: 0.14, y: 0.45))
            path.addQuadCurve(to: CGPoint(x: 0.5, y: 0.8), control: CGPoint(x: 0.86, y: 0.45))
            path.closeSubpath()
            return path
        }
    }

    static func shade(_ color: RGBA, _ amount: Double) -> RGBA {
        amount >= 0
            ? RGBA(color.r + (1 - color.r) * amount, color.g + (1 - color.g) * amount, color.b + (1 - color.b) * amount, color.a)
            : RGBA(color.r * (1 + amount), color.g * (1 + amount), color.b * (1 + amount), color.a)
    }

    static func draw(_ cut: GemCut, color: RGBA, setting: CharmFinish, in ctx: CGContext, pixels: Int) {
        let stone = outline(cut)
        let box = stone.boundingBox
        CharmArtwork.drawBail(ctx, to: box.maxY + 0.03, finish: setting)

        // The setting: the same outline, a little larger, in metal.
        var grow = CGAffineTransform(translationX: box.midX, y: box.midY).scaledBy(x: 1.13, y: 1.1).translatedBy(x: -box.midX, y: -box.midY)
        if let bezel = stone.copy(using: &grow),
           let mask = DrawnCharms.mask(pixels, { $0.addPath(bezel) }) {
            CharmArtwork.drawMetal(ctx, mask: mask, rect: CGRect(x: 0, y: 0, width: 1, height: 1), finish: setting, depth: 1)
        }

        ctx.saveGState()
        ctx.addPath(stone)
        ctx.clip()
        let light = CGPoint(x: box.minX + box.width * 0.35, y: box.minY + box.height * 0.72)
        CharmArtwork.radialGradient(ctx, centre: light, radius: max(box.width, box.height) * 0.85,
                                    colors: [shade(color, 0.55), color, shade(color, -0.45)])

        switch cut {
        case .cabochon:
            break
        case .opal:
            // Play of colour: soft patches of the spectrum under the surface.
            let patches: [(CGPoint, RGBA)] = [
                (CGPoint(x: 0.4, y: 0.6), RGBA(hex: 0x5EF0C8, alpha: 0.55)), (CGPoint(x: 0.6, y: 0.4), RGBA(hex: 0xFF7AB6, alpha: 0.5)),
                (CGPoint(x: 0.45, y: 0.3), RGBA(hex: 0x7AA8FF, alpha: 0.55)), (CGPoint(x: 0.62, y: 0.66), RGBA(hex: 0xFFD36B, alpha: 0.5)),
            ]
            for (point, tint) in patches {
                CharmArtwork.radialGradient(ctx, centre: point, radius: 0.16, colors: [tint, RGBA(tint.r, tint.g, tint.b, 0)])
            }
        default:
            // Facets: a table in the middle and lines running out to the girdle.
            let centre = CGPoint(x: box.midX, y: box.midY)
            let table = min(box.width, box.height) * 0.26
            var corners: [CGPoint] = []
            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4 + .pi / 8
                corners.append(CGPoint(x: centre.x + cos(angle) * table, y: centre.y + sin(angle) * table))
            }
            ctx.setLineWidth(0.006)
            ctx.setStrokeColor(RGBA(1, 1, 1, 0.38).cg)
            ctx.addLines(between: corners + [corners[0]])
            ctx.strokePath()
            ctx.setStrokeColor(RGBA(1, 1, 1, 0.2).cg)
            for corner in corners {
                ctx.move(to: corner)
                ctx.addLine(to: CGPoint(x: centre.x + (corner.x - centre.x) * 4, y: centre.y + (corner.y - centre.y) * 4))
            }
            ctx.strokePath()
            ctx.setFillColor(RGBA(1, 1, 1, 0.12).cg)
            ctx.addLines(between: corners)
            ctx.closePath()
            ctx.fillPath()
        }
        ctx.restoreGState()

        // A glint, so the stone reads as polished.
        let glint = CGPoint(x: box.minX + box.width * 0.32, y: box.minY + box.height * 0.74)
        let size = min(box.width, box.height) * 0.16
        ctx.saveGState()
        ctx.setFillColor(RGBA(1, 1, 1, 0.9).cg)
        ctx.addPath(DrawnCharms.starPath(centre: glint, outer: size, inner: size * 0.22, points: 4))
        ctx.fillPath()
        ctx.restoreGState()
    }
}
