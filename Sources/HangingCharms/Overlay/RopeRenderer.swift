import AppKit
import QuartzCore
import HangingCharmsCore

/// Draws the rope, the charms and the glow as Core Animation layers.
///
/// Physics runs in y-down canvas points; layers are y-up. Every conversion happens here.
/// Layers keep the cost of a frame on the GPU: the only per-frame CPU work is one rope
/// path and a position and rotation per charm.
@MainActor
final class RopeRenderer {
    let root = CALayer()
    private let glow = CAGradientLayer()
    private let ropeBase = CAShapeLayer()
    private let ropeDetail = CAShapeLayer()
    private let grapple = CALayer()
    private let beadLayer = CAShapeLayer()
    private let beadShine = CAShapeLayer()
    private var charmLayers: [CALayer] = []
    private var beadSpacing: CGFloat?
    private var beadDiameter: CGFloat = 6
    private var ropeWidth: CGFloat = 3

    var charmLayerCount: Int { charmLayers.count }
    var charmLayerSizes: [CGFloat] { charmLayers.map(\.bounds.width) }
    var isGrappleShown: Bool { !grapple.isHidden && grapple.contents != nil }
    var beadsDrawn: Bool { !beadLayer.isHidden && !(beadLayer.path?.boundingBox.isEmpty ?? true) }

    private var canvasHeight: CGFloat = 0
    private var scale: CGFloat = 2
    private var unit: CGFloat = 260

    init() {
        root.masksToBounds = false
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.opacity = 0
        for layer in [ropeBase, ropeDetail] {
            layer.fillColor = nil
            layer.lineJoin = .round
        }
        beadLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        beadLayer.shadowOpacity = 0.35
        beadLayer.shadowRadius = 1.5
        beadLayer.shadowOffset = CGSize(width: 0, height: -1)
        beadShine.fillColor = CGColor(gray: 1, alpha: 0.55)
        grapple.contentsGravity = .resizeAspect
        root.addSublayer(glow)
        root.addSublayer(ropeBase)
        root.addSublayer(ropeDetail)
        root.addSublayer(beadLayer)
        root.addSublayer(beadShine)
        root.addSublayer(grapple)
    }

    func attach(to view: NSView) {
        guard let host = view.layer else { return }
        root.frame = host.bounds
        root.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        host.addSublayer(root)
    }

    func setCanvas(height: CGFloat, scale: CGFloat) {
        canvasHeight = height
        self.scale = scale
        root.contentsScale = scale
        [glow, ropeBase, ropeDetail, beadLayer, beadShine, grapple].forEach { $0.contentsScale = scale }
        charmLayers.forEach { $0.contentsScale = scale }
    }

    private func flip(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: canvasHeight - point.y) }

    // MARK: - Configuration

    /// - Parameter linkSize: Multiplier on chain links and twists along the cord.
    func configure(look: RopeAppearance, unit: Double, ropeGlow: Bool = false, linkSize: Double = 1) {
        self.unit = unit
        // Half a point is the thinnest line that still reads on a Retina display.
        let width = max(0.5, unit * look.widthScale)
        ropeWidth = width
        let link = width * max(0.2, linkSize)

        ropeBase.strokeColor = look.primary.cg
        ropeBase.lineWidth = width
        ropeBase.lineCap = .round
        ropeBase.lineDashPattern = nil
        ropeBase.shadowOpacity = 0
        ropeDetail.isHidden = false
        ropeDetail.lineDashPhase = 0
        ropeDetail.shadowOpacity = 0

        switch look.pattern {
        case .twisted:
            ropeDetail.strokeColor = look.secondary.cg
            ropeDetail.lineWidth = width * 0.5
            ropeDetail.lineCap = .butt
            ropeDetail.lineDashPattern = [NSNumber(value: link * 0.9), NSNumber(value: link * 0.9)]
        case .braided:
            ropeDetail.strokeColor = look.secondary.cg
            ropeDetail.lineWidth = width * 0.7
            ropeDetail.lineCap = .round
            ropeDetail.lineDashPattern = [NSNumber(value: link * 0.4), NSNumber(value: link * 0.9)]
        case .chain:
            ropeBase.lineCap = .round
            ropeBase.lineDashPattern = [NSNumber(value: link * 1.5), NSNumber(value: link * 0.7)]
            ropeDetail.strokeColor = look.secondary.cg
            ropeDetail.lineWidth = width * 0.42
            ropeDetail.lineCap = .round
            ropeDetail.lineDashPattern = [NSNumber(value: link * 1.0), NSNumber(value: link * 1.2)]
            ropeDetail.lineDashPhase = -link * 0.35
        case .glowing:
            ropeBase.shadowColor = look.primary.cg
            ropeBase.shadowRadius = width * 3
            ropeBase.shadowOpacity = 1
            ropeBase.shadowOffset = .zero
            ropeDetail.strokeColor = CGColor(gray: 1, alpha: 0.9)
            ropeDetail.lineWidth = width * 0.45
            ropeDetail.lineCap = .round
            ropeDetail.lineDashPattern = nil
        case .fine:
            ropeBase.shadowColor = CGColor(gray: 0, alpha: 1)
            ropeBase.shadowRadius = 1.5
            ropeBase.shadowOpacity = 0.35
            ropeBase.shadowOffset = CGSize(width: 0, height: -1)
            ropeDetail.isHidden = true
        }
        if look.pattern != .glowing && look.pattern != .fine {
            ropeBase.shadowColor = CGColor(gray: 0, alpha: 1)
            ropeBase.shadowOpacity = 0.3
            ropeBase.shadowRadius = 2
            ropeBase.shadowOffset = CGSize(width: 0, height: -1.5)
        }
        // A light along the cord, on any pattern: the shadow becomes a coloured halo.
        if ropeGlow, look.pattern != .glowing {
            ropeBase.shadowColor = look.primary.cg
            ropeBase.shadowRadius = max(4, width * 2.5)
            ropeBase.shadowOpacity = 0.95
            ropeBase.shadowOffset = .zero
        }
    }

    /// What the rope hangs from. `eyeY` is where the rope ties on, from the image bottom.
    func setGrapple(_ image: CGImage?, side: CGFloat, eyeY: CGFloat) {
        grapple.isHidden = image == nil
        grapple.contents = image
        grapple.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        grapple.anchorPoint = CGPoint(x: 0.5, y: eyeY)
    }

    /// Beads along the cord above the top charm. `spacing` nil means no beads.
    func setBeads(spacing: CGFloat?, color: RGBA, diameter: CGFloat) {
        beadSpacing = spacing
        beadDiameter = max(2, diameter)
        beadLayer.fillColor = color.cg
        beadLayer.isHidden = spacing == nil
        beadShine.isHidden = spacing == nil
    }

    /// Sets the charm images, from the anchor down.
    func setCharms(_ images: [CGImage?], diameters: [CGFloat]) {
        while charmLayers.count < images.count {
            let layer = CALayer()
            layer.contentsGravity = .resizeAspect
            layer.anchorPoint = CGPoint(x: 0.5, y: CharmArtwork.ringAnchorY)
            layer.contentsScale = scale
            root.addSublayer(layer)
            charmLayers.append(layer)
        }
        while charmLayers.count > images.count {
            charmLayers.removeLast().removeFromSuperlayer()
        }
        for (index, layer) in charmLayers.enumerated() {
            layer.contents = images[index]
            layer.bounds = CGRect(x: 0, y: 0, width: diameters[index], height: diameters[index])
        }
    }

    func setGlow(enabled: Bool, color: RGBA, diameter: CGFloat, intensity: Double = 0.85, size: Double = 1, breathing: Bool = true) {
        guard enabled else {
            glow.removeAllAnimations()
            glow.opacity = 0
            return
        }
        let strength = min(max(intensity, 0), 1)
        glow.colors = [color.cg.copy(alpha: 0.65)!, color.cg.copy(alpha: 0.22)!, color.cg.copy(alpha: 0)!]
        glow.locations = [0, 0.45, 1]
        let side = diameter * 2.4 * CGFloat(size)
        glow.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        glow.opacity = Float(strength)
        glow.removeAnimation(forKey: "breathe")
        if breathing {
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = strength * 0.6
            breathe.toValue = strength
            breathe.duration = 2.6
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(breathe, forKey: "breathe")
        }
    }

    // MARK: - Per frame

    func render(_ rope: RopeSimulation) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let path = CGMutablePath()
        let points = rope.points.map { flip($0.position) }
        appendCatmullRom(points, to: path)
        ropeBase.path = path
        ropeDetail.path = path
        grapple.position = flip(rope.anchor)
        updateBeads(rope, flipped: points)

        for (slot, layer) in charmLayers.enumerated() where slot < rope.layout.slots.count {
            let direction = rope.charmDirection(slot: slot)
            layer.position = flip(rope.charmRing(slot: slot))
            layer.setAffineTransform(CGAffineTransform(rotationAngle: atan2(direction.x, direction.y)))
        }
        if let last = rope.layout.slots.indices.last {
            glow.position = flip(rope.charmCentre(slot: last))
        }
        CATransaction.commit()
    }

    /// Beads ride the cord from the grapple down to the first charm, where the charm's
    /// own hook takes over. Their places are re-measured along the rope every frame, so
    /// they move with it rather than being drawn on a still picture of it.
    private func updateBeads(_ rope: RopeSimulation, flipped points: [CGPoint]) {
        guard let spacing = beadSpacing, let firstCharm = rope.layout.slots.first?.node, firstCharm > 0 else {
            beadLayer.path = nil
            beadShine.path = nil
            return
        }
        let cord = Array(points[0...min(firstCharm, points.count - 1)])
        var lengths: [CGFloat] = [0]
        for index in 1..<cord.count { lengths.append(lengths[index - 1] + hypot(cord[index].x - cord[index - 1].x, cord[index].y - cord[index - 1].y)) }
        let total = lengths.last ?? 0
        let radius = beadDiameter / 2
        let places = BeadLayout.positions(length: Double(total), spacing: Double(spacing), margin: Double(radius * 3))
        let beads = CGMutablePath(), shine = CGMutablePath()
        var segment = 1
        for place in places.map({ CGFloat($0) }) {
            while segment < lengths.count - 1, lengths[segment] < place { segment += 1 }
            let span = max(0.0001, lengths[segment] - lengths[segment - 1])
            let t = (place - lengths[segment - 1]) / span
            let a = cord[segment - 1], b = cord[segment]
            let centre = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            beads.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            let gloss = radius * 0.35
            shine.addEllipse(in: CGRect(x: centre.x - radius * 0.45 - gloss / 2, y: centre.y + radius * 0.25 - gloss / 2, width: gloss, height: gloss))
        }
        beadLayer.path = beads
        beadShine.path = shine
    }

    /// A smooth curve through every node (centripetal-free uniform Catmull-Rom).
    private func appendCatmullRom(_ points: [CGPoint], to path: CGMutablePath) {
        guard let first = points.first else { return }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return
        }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(points.count - 1, index + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }
}
