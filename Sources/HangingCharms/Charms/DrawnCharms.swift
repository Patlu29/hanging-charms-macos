import AppKit
import CoreText
import HangingCharmsCore

/// The hand-drawn charms: vector paths in a y-up unit square.
@MainActor
enum DrawnCharms {
    private static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func draw(_ shape: DrawnShape, in ctx: CGContext, pixels: Int) {
        switch shape {
        case .evilEye: evilEye(ctx, pixels)
        case .crescent: metal(ctx, pixels, finish: .gold, bailTo: 0.82) { crescentPath($0) }
        case .fourLeafClover: clover(ctx, pixels)
        case .horseshoe: horseshoe(ctx, pixels)
        case .heart: heart(ctx, pixels)
        case .star: metal(ctx, pixels, finish: .gold, bailTo: 0.83) { $0.addPath(starPath(centre: CGPoint(x: 0.5, y: 0.46), outer: 0.38, inner: 0.165, points: 5)) }
        case .sun: sun(ctx, pixels)
        case .crystal: crystal(ctx, pixels)
        case .luckySeven: luckySeven(ctx, pixels)
        case .lotus: lotus(ctx, pixels)
        case .planet: planet(ctx, pixels)
        case .dreamcatcher: dreamcatcher(ctx, pixels)
        }
    }

    // MARK: - Shared

    /// Renders `build` (paths in unit space, filled) into an alpha mask.
    static func mask(_ pixels: Int, evenOdd: Bool = false, _ build: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: CGFloat(pixels), y: CGFloat(pixels))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        build(ctx)
        ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
        return ctx.makeImage()
    }

    static func metal(_ ctx: CGContext, _ pixels: Int, finish: CharmFinish, bailTo top: CGFloat, evenOdd: Bool = false,
                      depth: CGFloat = 1, _ build: (CGContext) -> Void) {
        let ring = CharmArtwork.ringFinish(for: finish)
        CharmArtwork.drawRing(ctx, finish: ring)
        CharmArtwork.drawBail(ctx, to: top, finish: ring)
        if let shape = mask(pixels, evenOdd: evenOdd, build) {
            CharmArtwork.drawMetal(ctx, mask: shape, rect: unit, finish: finish, depth: depth)
        }
    }

    static func starPath(centre: CGPoint, outer: CGFloat, inner: CGFloat, points: Int, rotation: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = (.pi / 2) + rotation + CGFloat(index) * .pi / CGFloat(points)
            let point = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    static func heartPath(centre: CGPoint, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let s = size
        let bottom = CGPoint(x: centre.x, y: centre.y - s * 0.55)
        path.move(to: bottom)
        path.addCurve(to: CGPoint(x: centre.x - s * 0.5, y: centre.y + s * 0.18),
                      control1: CGPoint(x: centre.x - s * 0.12, y: centre.y - s * 0.38),
                      control2: CGPoint(x: centre.x - s * 0.5, y: centre.y - s * 0.12))
        path.addArc(center: CGPoint(x: centre.x - s * 0.25, y: centre.y + s * 0.2), radius: s * 0.25,
                    startAngle: .pi * 1.05, endAngle: 0, clockwise: true)
        path.addArc(center: CGPoint(x: centre.x + s * 0.25, y: centre.y + s * 0.2), radius: s * 0.25,
                    startAngle: .pi, endAngle: -.pi * 0.05, clockwise: true)
        path.addCurve(to: bottom,
                      control1: CGPoint(x: centre.x + s * 0.5, y: centre.y - s * 0.12),
                      control2: CGPoint(x: centre.x + s * 0.12, y: centre.y - s * 0.38))
        path.closeSubpath()
        return path
    }

    static func crescentPath(_ ctx: CGContext) {
        // Clip away the bite first (everything outside it), then fill the moon, so no
        // antialiased trace of the bite's edge is left behind.
        ctx.addRect(CGRect(x: -1, y: -1, width: 3, height: 3))
        ctx.addEllipse(in: CharmArtwork.disc(CGPoint(x: 0.63, y: 0.53), 0.3))
        ctx.clip(using: .evenOdd)
        ctx.addEllipse(in: CharmArtwork.disc(CGPoint(x: 0.5, y: 0.45), 0.37))
    }

    // MARK: - Charms

    static func evilEye(_ ctx: CGContext, _ pixels: Int) {
        let centre = CGPoint(x: 0.5, y: 0.44)
        CharmArtwork.drawRing(ctx, finish: .gold)
        CharmArtwork.drawBail(ctx, to: centre.y + 0.39, finish: .gold)
        let layers: [(CGFloat, RGBA, RGBA)] = [
            (0.39, RGBA(hex: 0xA87A16), RGBA(hex: 0xF2C14E)), // gold bezel
            (0.355, RGBA(hex: 0x0F2A78), RGBA(hex: 0x2B5BD8)),
            (0.255, RGBA(hex: 0xDDE6F2), RGBA(hex: 0xFFFFFF)),
            (0.175, RGBA(hex: 0x2A86D0), RGBA(hex: 0x86CBFF)),
            (0.085, RGBA(hex: 0x050608), RGBA(hex: 0x2A2C36)),
        ]
        for (radius, dark, light) in layers {
            ctx.saveGState()
            ctx.addEllipse(in: CharmArtwork.disc(centre, radius))
            ctx.clip()
            CharmArtwork.linearGradient(ctx, from: CGPoint(x: 0.5, y: centre.y - radius), to: CGPoint(x: 0.5, y: centre.y + radius), colors: [dark, light])
            ctx.restoreGState()
        }
        // Glass dome highlight.
        ctx.saveGState()
        ctx.setFillColor(RGBA(1, 1, 1, 0.55).cg)
        ctx.fillEllipse(in: CGRect(x: 0.30, y: 0.56, width: 0.16, height: 0.09))
        ctx.restoreGState()
        CharmArtwork.sheen(ctx, in: CharmArtwork.disc(centre, 0.36))
    }

    static func clover(_ ctx: CGContext, _ pixels: Int) {
        let centre = CGPoint(x: 0.5, y: 0.5)
        metal(ctx, pixels, finish: .enamelGreen, bailTo: 0.82) { c in
            for leaf in 0..<4 {
                let angle = CGFloat(leaf) * .pi / 2 + .pi / 4
                let along = CGPoint(x: cos(angle), y: sin(angle))
                let side = CGPoint(x: -along.y, y: along.x)
                for lobe in [-1.0, 1.0] {
                    let x = centre.x + along.x * 0.17 + side.x * 0.075 * lobe
                    let y = centre.y + along.y * 0.17 + side.y * 0.075 * lobe
                    c.addEllipse(in: CharmArtwork.disc(CGPoint(x: x, y: y), 0.105))
                }
            }
            c.addEllipse(in: CharmArtwork.disc(centre, 0.07))
            // Stem.
            let stem = CGMutablePath()
            stem.move(to: CGPoint(x: 0.49, y: 0.48))
            stem.addQuadCurve(to: CGPoint(x: 0.62, y: 0.07), control: CGPoint(x: 0.5, y: 0.2))
            c.addPath(stem.copy(strokingWithWidth: 0.045, lineCap: .round, lineJoin: .round, miterLimit: 1))
        }
        // Leaf veins.
        ctx.saveGState()
        ctx.setStrokeColor(RGBA(hex: 0xC8F5D4, alpha: 0.7).cg)
        ctx.setLineWidth(0.008)
        for leaf in 0..<4 {
            let angle = CGFloat(leaf) * .pi / 2 + .pi / 4
            ctx.move(to: CGPoint(x: 0.5, y: 0.5))
            ctx.addLine(to: CGPoint(x: 0.5 + cos(angle) * 0.24, y: 0.5 + sin(angle) * 0.24))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func horseshoe(_ ctx: CGContext, _ pixels: Int) {
        let centre = CGPoint(x: 0.5, y: 0.5)
        metal(ctx, pixels, finish: .silver, bailTo: 0.84) { c in
            let arc = CGMutablePath()
            arc.addArc(center: centre, radius: 0.27, startAngle: .pi * 0.28, endAngle: .pi * 0.72, clockwise: true)
            c.addPath(arc.copy(strokingWithWidth: 0.13, lineCap: .butt, lineJoin: .round, miterLimit: 1))
        }
        ctx.saveGState()
        ctx.setFillColor(CharmFinish.silver.shadow.cg)
        // Nail holes along the shoe, which opens upward.
        for degrees in [32.0, -8, -48, -132, -172, 148] {
            let angle = degrees * .pi / 180
            let p = CGPoint(x: centre.x + cos(angle) * 0.27, y: centre.y + sin(angle) * 0.27)
            ctx.fillEllipse(in: CharmArtwork.disc(p, 0.018))
        }
        ctx.restoreGState()
    }

    static func heart(_ ctx: CGContext, _ pixels: Int) {
        let centre = CGPoint(x: 0.5, y: 0.52)
        metal(ctx, pixels, finish: .gold, bailTo: 0.72) { $0.addPath(heartPath(centre: centre, size: 0.8)) }
        if let inset = mask(pixels, { $0.addPath(heartPath(centre: CGPoint(x: 0.5, y: 0.525), size: 0.62)) }) {
            CharmArtwork.drawMetal(ctx, mask: inset, rect: unit, finish: .enamelRed, depth: 0.35)
        }
    }

    static func sun(_ ctx: CGContext, _ pixels: Int) {
        let centre = CGPoint(x: 0.5, y: 0.46)
        metal(ctx, pixels, finish: .gold, bailTo: 0.84) { c in
            c.addPath(starPath(centre: centre, outer: 0.38, inner: 0.2, points: 12))
        }
        if let face = mask(pixels, { $0.addEllipse(in: CharmArtwork.disc(centre, 0.17)) }) {
            CharmArtwork.drawMetal(ctx, mask: face, rect: unit, finish: .bronze, depth: 0.4)
        }
    }

    static func crystal(_ ctx: CGContext, _ pixels: Int) {
        let points = [CGPoint(x: 0.5, y: 0.84), CGPoint(x: 0.66, y: 0.68), CGPoint(x: 0.66, y: 0.24),
                      CGPoint(x: 0.5, y: 0.05), CGPoint(x: 0.34, y: 0.24), CGPoint(x: 0.34, y: 0.68)]
        metal(ctx, pixels, finish: .enamelPurple, bailTo: 0.84) { c in
            c.addLines(between: points)
            c.closePath()
        }
        ctx.saveGState()
        ctx.setStrokeColor(RGBA(hex: 0xE8DCFF, alpha: 0.75).cg)
        ctx.setLineWidth(0.008)
        let core = [CGPoint(x: 0.5, y: 0.72), CGPoint(x: 0.56, y: 0.62), CGPoint(x: 0.56, y: 0.28), CGPoint(x: 0.5, y: 0.16), CGPoint(x: 0.44, y: 0.28), CGPoint(x: 0.44, y: 0.62)]
        ctx.addLines(between: core + [core[0]])
        for (outer, inner) in zip(points, core) {
            ctx.move(to: outer)
            ctx.addLine(to: inner)
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func luckySeven(_ ctx: CGContext, _ pixels: Int) {
        let centre = CGPoint(x: 0.5, y: 0.45)
        CharmArtwork.drawMedallion(ctx, symbol: nil, rim: .gold, face: .pearl, pixels: pixels)
        // The 7, set in red enamel.
        let font = NSFont.systemFont(ofSize: CGFloat(pixels) * 0.5, weight: .black)
        if let seven = mask(pixels, { c in
            c.saveGState()
            c.scaleBy(x: 1 / CGFloat(pixels), y: 1 / CGFloat(pixels))
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "7", attributes: [.font: font]))
            let bounds = CTLineGetImageBounds(line, c)
            c.textPosition = CGPoint(x: centre.x * CGFloat(pixels) - bounds.midX, y: centre.y * CGFloat(pixels) - bounds.midY)
            CTLineDraw(line, c)
            c.restoreGState()
        }) {
            CharmArtwork.drawMetal(ctx, mask: seven, rect: unit, finish: .enamelRed, depth: 0.5)
        }
    }

    static func lotus(_ ctx: CGContext, _ pixels: Int) {
        let base = CGPoint(x: 0.5, y: 0.22)
        func petal(_ c: CGContext, angle: CGFloat, length: CGFloat, width: CGFloat) {
            c.saveGState()
            c.translateBy(x: base.x, y: base.y)
            c.rotate(by: angle)
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addQuadCurve(to: CGPoint(x: 0, y: length), control: CGPoint(x: -width, y: length * 0.55))
            path.addQuadCurve(to: .zero, control: CGPoint(x: width, y: length * 0.55))
            c.addPath(path)
            c.restoreGState()
        }
        metal(ctx, pixels, finish: .roseGold, bailTo: 0.82) { c in
            for (angle, length) in [(-1.05, 0.42), (-0.52, 0.52), (0.0, 0.6), (0.52, 0.52), (1.05, 0.42)] as [(CGFloat, CGFloat)] {
                petal(c, angle: angle, length: length, width: 0.17)
            }
            c.addEllipse(in: CGRect(x: 0.22, y: 0.12, width: 0.56, height: 0.16))
        }
        if let inner = mask(pixels, { c in
            for (angle, length) in [(-0.45, 0.36), (0.0, 0.44), (0.45, 0.36)] as [(CGFloat, CGFloat)] {
                petal(c, angle: angle, length: length, width: 0.1)
            }
        }) {
            CharmArtwork.drawMetal(ctx, mask: inner, rect: unit, finish: .pearl, depth: 0.4)
        }
    }

    static func planet(_ ctx: CGContext, _ pixels: Int) {
        let centre = CGPoint(x: 0.5, y: 0.45)
        let ringPath: (CGContext) -> Void = { c in
            c.saveGState()
            c.translateBy(x: centre.x, y: centre.y)
            c.rotate(by: -0.35)
            let ellipse = CGPath(ellipseIn: CGRect(x: -0.42, y: -0.1, width: 0.84, height: 0.2), transform: nil)
            c.addPath(ellipse.copy(strokingWithWidth: 0.04, lineCap: .round, lineJoin: .round, miterLimit: 1))
            c.restoreGState()
        }
        CharmArtwork.drawRing(ctx, finish: .silver)
        CharmArtwork.drawBail(ctx, to: centre.y + 0.25, finish: .silver)
        if let ring = mask(pixels, ringPath) {
            CharmArtwork.drawMetal(ctx, mask: ring, rect: unit, finish: .silver, depth: 0.5)
        }
        if let globe = mask(pixels, { $0.addEllipse(in: CharmArtwork.disc(centre, 0.25)) }) {
            CharmArtwork.drawMetal(ctx, mask: globe, rect: unit, finish: .enamelPurple, depth: 0.8)
        }
        // The front half of the ring passes over the planet.
        if let front = mask(pixels, { c in
            c.saveGState()
            c.clip(to: CGRect(x: 0, y: 0, width: 1, height: centre.y + 0.01))
            ringPath(c)
            c.restoreGState()
        }) {
            CharmArtwork.drawMetal(ctx, mask: front, rect: unit, finish: .silver, depth: 0.3)
        }
    }

    static func dreamcatcher(_ ctx: CGContext, _ pixels: Int) {
        let hoop = CGPoint(x: 0.5, y: 0.6)
        let radius: CGFloat = 0.22
        metal(ctx, pixels, finish: .bronze, bailTo: hoop.y + radius) { c in
            let ring = CGPath(ellipseIn: CharmArtwork.disc(hoop, radius), transform: nil)
            c.addPath(ring.copy(strokingWithWidth: 0.035, lineCap: .round, lineJoin: .round, miterLimit: 1))
            // Strings to the feathers.
            for x in [0.36, 0.5, 0.64] as [CGFloat] {
                let s = CGMutablePath()
                s.move(to: CGPoint(x: x, y: hoop.y - radius * (x == 0.5 ? 1 : 0.85)))
                s.addLine(to: CGPoint(x: x, y: 0.28))
                c.addPath(s.copy(strokingWithWidth: 0.012, lineCap: .round, lineJoin: .round, miterLimit: 1))
            }
        }
        // Web.
        ctx.saveGState()
        ctx.setStrokeColor(RGBA(hex: 0xF3EEE6, alpha: 0.9).cg)
        ctx.setLineWidth(0.006)
        ctx.addPath(starPath(centre: hoop, outer: radius * 0.95, inner: radius * 0.45, points: 7))
        ctx.addPath(starPath(centre: hoop, outer: radius * 0.45, inner: radius * 0.2, points: 7, rotation: .pi / 7))
        ctx.strokePath()
        ctx.setFillColor(CharmFinish.enamelBlue.base.cg)
        ctx.fillEllipse(in: CharmArtwork.disc(hoop, 0.025))
        ctx.restoreGState()
        // Feathers.
        let colours: [CharmFinish] = [.enamelBlue, .pearl, .enamelPurple]
        for (x, finish) in zip([0.36, 0.5, 0.64] as [CGFloat], colours) {
            if let feather = mask(pixels, { c in
                c.addEllipse(in: CGRect(x: x - 0.045, y: 0.05, width: 0.09, height: 0.25))
            }) {
                CharmArtwork.drawMetal(ctx, mask: feather, rect: unit, finish: finish, depth: 0.4)
            }
        }
    }
}
