import AppKit
import QuartzCore
import HangingCharmsCore

/// Owns the overlay panel, the simulation and the frame loop, and applies settings.
@MainActor
final class OverlayController: NSObject {
    private let store: SettingsStore
    private let library: CharmLibrary
    private let audio: AudioService
    var openCustomize: ((CustomizePage) -> Void)?
    var onImportPicture: ((URL) -> Void)?

    private var panel: OverlayPanel?
    private var view: OverlayView?
    private let renderer = RopeRenderer()
    private var rope: RopeSimulation?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var screen: NSScreen?

    private var monitors: [Any] = []
    private let fullScreen = FullScreenWatcher()
    private var timeTimer: Timer?
    private var profile: RopeTimeProfile = .baseline
    private var resolved: [ResolvedCharm] = []

    private var dragSamples: [(time: TimeInterval, point: CGPoint)] = []
    private var lastCursor: (time: TimeInterval, point: CGPoint)?
    private var isPointerOverCharm = false
    private var isRelaxedRate = false

    init(store: SettingsStore, library: CharmLibrary, audio: AudioService) {
        self.store = store
        self.library = library
        self.audio = audio
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        store.observe { [weak self] old, new in self?.apply(new, old: old) }
        fullScreen.onChange = { [weak self] _ in self?.updateVisibility() }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemWoke), name: NSWorkspace.didWakeNotification, object: nil)

        installMouseMonitors()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTimeProfile() }
        }
        rebuild()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        fullScreen.stop()
        timeTimer?.invalidate()
        panel?.orderOut(nil)
    }

    // MARK: - Applying settings

    private func apply(_ new: AppSettings, old: AppSettings) {
        if new.displayKey != old.displayKey {
            rebuild()
            return
        }
        if new.charmIDs != old.charmIDs || new.ropeStyle != old.ropeStyle || new.ropeLength != old.ropeLength
            || new.charmSize != old.charmSize || new.elastic != old.elastic || new.timeOfDay != old.timeOfDay
            || new.charmScales != old.charmScales || new.swingWeight != old.swingWeight || new.settleSpeed != old.settleSpeed {
            refreshTimeProfile(force: true)
            reconfigureRope()
        } else if new.resolvedRopeAppearance != old.resolvedRopeAppearance || new.ropeGlow != old.ropeGlow
            || new.linkSize != old.linkSize || new.beads != old.beads || new.beadColor != old.beadColor
            || new.beadSize != old.beadSize || new.grappleStyle != old.grappleStyle
            || new.grappleFinish != old.grappleFinish || new.grappleSize != old.grappleSize {
            configureRenderer()
            if Connector.from(new) != Connector.from(old) { updateCharmImages() }
            if let rope { renderer.render(rope) }
        }
        if new.charmShadow != old.charmShadow || Connector.from(new) != Connector.from(old) { updateCharmImages() }
        if new.horizontalPosition != old.horizontalPosition || new.hangDrop != old.hangDrop
            || new.hangPoint != old.hangPoint || new.pinX != old.pinX || new.pinY != old.pinY {
            updateWindowTracking()
            placeAnchor()
        }
        if new.breeze != old.breeze || new.reduceMotion != old.reduceMotion { applyBreeze() }
        if new.opacity != old.opacity { panel?.alphaValue = new.opacity }
        if new.level != old.level { panel?.setLevel(new.level) }
        if new.glow != old.glow || new.charmIDs != old.charmIDs || new.charmSize != old.charmSize
            || new.customGlowColor != old.customGlowColor || new.glowColor != old.glowColor
            || new.glowIntensity != old.glowIntensity || new.glowSize != old.glowSize
            || new.glowBreathing != old.glowBreathing || new.charmScales != old.charmScales { updateGlow() }
        if new.reduceMotion != old.reduceMotion, new.reduceMotion { rope?.reset(angle: 0); wake() }
        if new.hideInFullScreen != old.hideInFullScreen {
            new.hideInFullScreen ? fullScreen.start() : fullScreen.stop()
        }
        audio.enabled = new.sounds
        audio.volume = new.volume
        if new.isVisible != old.isVisible { updateVisibility() }
    }

    /// Builds the panel on the chosen display from scratch.
    private func rebuild() {
        let settings = store.settings
        let target = DisplayChoice.screen(for: settings.displayKey)
        screen = target

        displayLink?.invalidate()
        displayLink = nil
        panel?.orderOut(nil)

        let frame = target.frame
        let panel = OverlayPanel(frame: frame)
        let view = OverlayView(frame: CGRect(origin: .zero, size: frame.size))
        view.controller = self
        panel.contentView = view
        panel.alphaValue = settings.opacity
        panel.setLevel(settings.level)
        renderer.attach(to: view)
        renderer.setCanvas(height: frame.height, scale: target.backingScaleFactor)
        self.panel = panel
        self.view = view

        refreshTimeProfile(force: true)
        let configuration = makeConfiguration()
        let anchor = anchorPoint(on: target)
        resolved = settings.charmIDs.map(library.resolveOrDefault)
        let reduce = settings.reduceMotion || systemWantsCalm
        rope = RopeSimulation(
            configuration: configuration, anchor: anchor, charms: charmMetrics(),
            charmSize: settings.charmSize, massScale: settings.ropeStyle.physics.charmMassScale,
            startAngle: reduce ? 0 : nil
        )
        configureRenderer()
        updateCharmImages()
        updateGlow()
        applyBreeze()
        updateWindowTracking()

        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link

        fullScreen.screenFrame = frame
        if settings.hideInFullScreen { fullScreen.start() } else { fullScreen.stop() }
        audio.enabled = settings.sounds
        audio.volume = settings.volume
        if let rope { renderer.render(rope) }
        updateVisibility()
    }

    private func makeConfiguration() -> RopeConfiguration {
        let settings = store.settings
        let unit = OverlayPlacement.unit(for: (screen ?? NSScreen.screens[0]).frame)
        return RopeConfiguration.make(
            unit: unit, ropeLength: settings.ropeLength, style: settings.ropeStyle,
            profile: profile, elastic: settings.elastic,
            swingWeight: settings.swingWeight, settleSpeed: settings.settleSpeed
        )
    }

    private func reconfigureRope() {
        guard let rope else { return }
        let settings = store.settings
        resolved = settings.charmIDs.map(library.resolveOrDefault)
        let configuration = makeConfiguration()
        rope.reconfigure(
            configuration: configuration, charms: charmMetrics(),
            charmSize: settings.charmSize, massScale: settings.ropeStyle.physics.charmMassScale
        )
        configureRenderer()
        updateCharmImages()
        updateGlow()
        wake()
    }

    /// Each charm's metrics with its own size from Library applied. A larger charm is
    /// proportionally heavier, so it hangs and swings like a bigger piece of metal.
    private func charmMetrics() -> [CharmMetrics] {
        let settings = store.settings
        return zip(settings.charmIDs, resolved).map { id, charm in
            let scale = settings.scale(for: id)
            return CharmMetrics(mass: charm.metrics.mass * scale, sizeScale: charm.metrics.sizeScale * scale)
        }
    }

    private func configureRenderer() {
        let settings = store.settings
        let unit = rope?.configuration.charmUnit ?? 260
        let look = settings.resolvedRopeAppearance
        renderer.configure(look: look, unit: unit, ropeGlow: settings.ropeGlow, linkSize: settings.linkSize)

        let side = CGFloat(unit * 0.12 * settings.grappleSize)
        let palette = settings.grappleFinish.palette(rope: look)
        let scale = screen?.backingScaleFactor ?? 2
        let image = AttachmentArtwork.grappleImage(settings.grappleStyle, base: palette.base, highlight: palette.highlight,
                                                   shadow: palette.shadow, pixels: Int(side * scale))
        renderer.setGrapple(image, side: side, eyeY: AttachmentArtwork.eyeY(for: settings.grappleStyle))

        let cordWidth = max(0.5, unit * look.widthScale)
        renderer.setBeads(
            spacing: settings.beads.spacingFraction.map { CGFloat(unit * $0) },
            color: settings.beadColor,
            diameter: CGFloat(cordWidth * settings.beadSize)
        )
    }

    /// Re-reads custom charms after the library changes.
    func charmsChanged() {
        store.update { $0.prune(validIDs: library.validIDs) }
        reconfigureRope()
    }

    private func updateCharmImages() {
        guard let rope else { return }
        let scale = screen?.backingScaleFactor ?? 2
        let diameters = rope.layout.slots.map { CGFloat($0.radius * 2) }
        let shadow = store.settings.charmShadow
        CharmArtwork.connector = Connector.from(store.settings)
        let images = zip(resolved, diameters).map { CharmArtwork.image(for: $0, diameter: $1, scale: scale, shadow: shadow) }
        renderer.setCharms(images, diameters: diameters)
    }

    private func updateGlow() {
        guard let rope, let last = resolved.last, let slot = rope.layout.slots.last else { return }
        let settings = store.settings
        renderer.setGlow(
            enabled: settings.glow,
            color: settings.customGlowColor ? settings.glowColor : last.glowColor,
            diameter: CGFloat(slot.radius * 2),
            intensity: settings.glowIntensity,
            size: settings.glowSize,
            breathing: settings.glowBreathing
        )
    }

    private func placeAnchor() {
        guard let screen, let rope, !isMovingAnchor else { return }
        let anchor = anchorPoint(on: screen)
        guard anchor != rope.anchor else { return }
        rope.setAnchor(anchor)
        wake()
    }

    // MARK: - Hanging points

    /// Where the rope hangs from on `screen`, in canvas points, for the chosen mode.
    private func anchorPoint(on screen: NSScreen) -> CGPoint {
        let settings = store.settings
        let frame = screen.frame, visible = screen.visibleFrame
        let menuBar = OverlayPlacement.anchor(screenFrame: frame, visibleFrame: visible,
                                              horizontal: settings.horizontalPosition, drop: settings.hangDrop)
        switch settings.hangPoint {
        case .menuBar:
            return menuBar
        case .notch:
            func local(_ area: CGRect?) -> CGRect? {
                guard let area, !area.isEmpty else { return nil }
                // These are reported in global coordinates on some systems.
                return area.minX >= frame.minX && frame.minX != 0 ? area.offsetBy(dx: -frame.minX, dy: -frame.minY) : area
            }
            var point = OverlayPlacement.notchAnchor(screenFrame: frame, visibleFrame: visible,
                                                     leftArea: local(screen.auxiliaryTopLeftArea),
                                                     rightArea: local(screen.auxiliaryTopRightArea))
            point.y += min(max(settings.hangDrop, 0), visible.height * 0.5)
            return point
        case .frontWindow:
            guard let window = trackedWindow else { return menuBar }
            return OverlayPlacement.windowAnchor(window: window, screenFrame: frame, visibleFrame: visible,
                                                 primaryHeight: Double(NSScreen.screens.first?.frame.height ?? frame.height),
                                                 horizontal: settings.horizontalPosition)
        case .anywhere:
            return OverlayPlacement.pinnedAnchor(pin: CGPoint(x: settings.pinX, y: settings.pinY), screenFrame: frame)
        }
    }

    /// The front window's frame in CGWindowList coordinates, while hanging from it.
    private var trackedWindow: CGRect?
    private var windowTimer: Timer?

    private func updateWindowTracking() {
        guard store.settings.hangPoint == .frontWindow else {
            windowTimer?.invalidate()
            windowTimer = nil
            trackedWindow = nil
            return
        }
        refreshTrackedWindow()
        guard windowTimer == nil else { return }
        // Twenty looks a second is smooth enough for the anchor: the rope's own physics
        // turns each step of a moving window into a swing.
        windowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTrackedWindow() }
        }
    }

    private func refreshTrackedWindow() {
        // The self-test supplies its own window; the real ones would overwrite it.
        guard followsRealPointer, let screen else { return }
        let found = FrontWindow.frame(on: screen)
        // While our own app (Customize) is in front, keep hanging from the last window.
        guard let found else { return }
        guard found != trackedWindow else { return }
        trackedWindow = found
        placeAnchor()
    }

    /// For the self-test: hang from a made-up window.
    func simulateFrontWindow(_ frame: CGRect) {
        trackedWindow = frame
        placeAnchor()
    }

    // MARK: - Moving the top of the rope

    private var isMovingAnchor = false

    /// How close to the top of the rope a press has to be to pick it up.
    private var grappleReach: Double {
        let settings = store.settings
        guard settings.grappleStyle != .none, let rope else { return 12 }
        return rope.configuration.charmUnit * 0.12 * settings.grappleSize * 0.5 + 6
    }

    private func isOverGrapple(_ point: CGPoint) -> Bool {
        guard let rope else { return false }
        // The grapple sits above where the rope is tied, so measure from its middle.
        let eye = AttachmentArtwork.eyeY(for: store.settings.grappleStyle)
        let side = rope.configuration.charmUnit * 0.12 * store.settings.grappleSize
        let centre = CGPoint(x: rope.anchor.x, y: rope.anchor.y - (0.5 - Double(eye)) * side)
        return point.distance(to: centre) <= grappleReach
    }

    var testIsMovingAnchor: Bool { isMovingAnchor }

    // MARK: - Breeze

    private func applyBreeze() {
        let settings = store.settings
        let calm = settings.reduceMotion || systemWantsCalm
        rope?.breeze = calm ? 0 : settings.breeze.strength
        if rope?.breeze ?? 0 > 0 { wake() }
    }

    private func refreshTimeProfile(force: Bool = false) {
        let next: RopeTimeProfile = store.settings.timeOfDay ? .forDate(Date()) : .baseline
        guard next != profile || force else { return }
        let changed = next != profile
        profile = next
        if changed, !force { reconfigureRope() }
    }

    private func updateVisibility() {
        guard let panel else { return }
        let show = store.settings.isVisible && !(store.settings.hideInFullScreen && fullScreen.isFullScreen)
        if show {
            panel.orderFrontRegardless()
            wake()
        } else {
            panel.orderOut(nil)
            displayLink?.isPaused = true
        }
    }

    @objc private func screensChanged() {
        rebuild()
    }

    @objc private func systemWoke() {
        lastTimestamp = nil
        wake()
    }

    // MARK: - Frame loop

    private func wake() {
        rope?.wake()
        lastTimestamp = nil
        if panel?.isVisible == true { displayLink?.isPaused = false }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let rope else { return }
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard let previous = lastTimestamp else { return }
        rope.step(deltaTime: now - previous)
        renderer.render(rope)
        // A breeze alone is a slow sway: sixty frames a second is plenty and costs half.
        let relaxed = rope.breeze > 0 && !rope.isDragging && !isMovingAnchor
        if relaxed != isRelaxedRate {
            isRelaxedRate = relaxed
            link.preferredFrameRateRange = relaxed
                ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                : CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        // The charm moves under a still pointer too, so hover is re-checked every frame:
        // a swinging charm can then be caught, and a click where it used to be goes
        // through to the app underneath.
        updateHover()

        for impact in rope.drainImpacts() {
            audio.play(resolved.last?.sound ?? .metal, intensity: impact)
        }
        if rope.isSleeping && !rope.isDragging {
            link.isPaused = true
            lastTimestamp = nil
        }
    }

    // MARK: - Pointer

    /// Screen point (y-up, global) to physics point (y-down, canvas).
    private func canvasPoint(fromScreen point: CGPoint) -> CGPoint? {
        guard let panel else { return nil }
        let local = CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
        return CGPoint(x: local.x, y: panel.frame.height - local.y)
    }

    /// Physics point (y-down, canvas) to screen point (y-up, global).
    func screenPoint(fromCanvas point: CGPoint) -> CGPoint? {
        guard let panel else { return nil }
        return CGPoint(x: panel.frame.minX + point.x, y: panel.frame.minY + panel.frame.height - point.y)
    }

    /// Where a mouse event happened, in canvas points. Uses the event's own location, so
    /// a drag is measured where AppKit says it was, not wherever the cursor is by now.
    private func canvasPoint(of event: NSEvent) -> CGPoint? {
        guard let panel else { return nil }
        if event.window === panel {
            return CGPoint(x: event.locationInWindow.x, y: panel.frame.height - event.locationInWindow.y)
        }
        return canvasPoint(fromScreen: pointerLocation)
    }

    /// The pointer, in global screen points. The self-test replaces the real one.
    private var pointerLocation: CGPoint {
        followsRealPointer ? NSEvent.mouseLocation : (simulatedPointer ?? .zero)
    }

    /// Whether macOS's own Reduce Motion is on, and honoured.
    private var systemWantsCalm: Bool {
        honoursSystemReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Testing hooks

    /// The self-test turns this off to exercise motion on machines (such as CI runners)
    /// that have Reduce Motion on, then turns it back on to check it is honoured.
    var honoursSystemReduceMotion = true {
        didSet { applyBreeze() }
    }

    /// False while the self-test drives the overlay, so the real cursor and the real
    /// front window cannot interfere.
    var followsRealPointer = true
    private var simulatedPointer: CGPoint?
    var testRope: RopeSimulation? { rope }
    var testPanel: OverlayPanel? { panel }
    var testRenderer: RopeRenderer { renderer }
    var isFrameLoopPaused: Bool { displayLink?.isPaused ?? true }

    /// Moves the simulated pointer, as a mouse-moved event would.
    func simulatePointer(atScreen point: CGPoint) {
        simulatedPointer = point
        pointerMoved()
    }

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { if self?.followsRealPointer == true { self?.pointerMoved() } }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { if self?.followsRealPointer == true { self?.pointerMoved() } }
            return event
        }) { monitors.append(local) }
    }

    /// Lets the panel take the mouse only while the pointer is over a charm.
    /// - Returns: The pointer in canvas points, when there is a panel to measure against.
    @discardableResult
    private func updateHover() -> CGPoint? {
        guard let rope, let panel, panel.isVisible, !rope.isDragging, !isMovingAnchor,
              let point = canvasPoint(fromScreen: pointerLocation) else { return nil }
        let over = rope.canGrab(at: point) || isOverGrapple(point)
        if over != isPointerOverCharm {
            isPointerOverCharm = over
            panel.ignoresMouseEvents = !over
            (over ? NSCursor.openHand : NSCursor.arrow).set()
        }
        return point
    }

    private func pointerMoved() {
        guard let rope, let point = updateHover() else { return }

        let now = ProcessInfo.processInfo.systemUptime
        defer { lastCursor = (now, point) }
        let settings = store.settings
        guard settings.mouseReactive, !settings.reduceMotion, !systemWantsCalm else { return }
        // With no recent sample there is no speed to knock with, but the brush still has
        // to learn where the pointer is: otherwise it remembers being inside a charm the
        // pointer has long left, and treats the next quick pass as the same one.
        var velocity = CGPoint.zero
        if let last = lastCursor {
            let dt = now - last.time
            if dt > 0.001, dt < 0.2 { velocity = (point - last.point) / dt }
        }
        if rope.brush(at: point, velocity: velocity) { wake() }
    }

    func mouseDown(_ event: NSEvent) {
        guard let rope, let point = canvasPoint(of: event) else { return }
        // The charm swung away between the last hover check and this click: stop
        // holding the mouse so the next click reaches the app underneath.
        guard rope.canGrab(at: point) else {
            if isOverGrapple(point) {
                // Picking up the top of the rope, to hang it somewhere else.
                isMovingAnchor = true
                NSCursor.closedHand.set()
                wake()
                return
            }
            isPointerOverCharm = false
            panel?.ignoresMouseEvents = true
            NSCursor.arrow.set()
            return
        }
        if event.clickCount == 2, rope.canGrab(at: point) {
            openCustomize?(.library)
            return
        }
        if rope.beginDrag(at: point) {
            NSCursor.closedHand.set()
            dragSamples = [(event.timestamp, point)]
            wake()
        }
    }

    func mouseDragged(_ event: NSEvent) {
        if isMovingAnchor, let rope, let point = canvasPoint(of: event), let panel {
            let clamped = CGPoint(x: min(max(point.x, 8), panel.frame.width - 8),
                                  y: min(max(point.y, 0), panel.frame.height * 0.9))
            rope.setAnchor(clamped)
            wake()
            return
        }
        guard let rope, rope.isDragging, let point = canvasPoint(of: event) else { return }
        dragSamples.append((event.timestamp, point))
        dragSamples.removeAll { event.timestamp - $0.time > 0.08 }
        var velocity = CGPoint.zero
        if let first = dragSamples.first, event.timestamp - first.time > 0.001 {
            velocity = (point - first.point) / (event.timestamp - first.time)
        }
        rope.updateDrag(to: point, velocity: velocity)
        wake()
    }

    func mouseUp(_ event: NSEvent) {
        guard let rope else { return }
        if isMovingAnchor {
            mouseDragged(event)
            isMovingAnchor = false
            if let screen {
                let pin = OverlayPlacement.pin(for: rope.anchor, screenFrame: screen.frame)
                store.update {
                    $0.hangPoint = .anywhere
                    $0.pinX = pin.x
                    $0.pinY = pin.y
                }
            }
            isPointerOverCharm = false
            pointerMoved()
            return
        }
        if rope.isDragging {
            mouseDragged(event)
            rope.endDrag()
        }
        dragSamples = []
        isPointerOverCharm = false
        pointerMoved()
    }

    // MARK: - Context menu

    func showContextMenu(for event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Library…", action: #selector(menuLibrary), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Create a Charm…", action: #selector(menuCreate), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Appearance…", action: #selector(menuAppearance), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let ropes = NSMenuItem(title: "Rope", action: nil, keyEquivalent: "")
        let ropeMenu = NSMenu()
        for style in RopeStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: #selector(menuRope(_:)), keyEquivalent: "")
            item.representedObject = style.rawValue
            item.state = store.settings.ropeStyle == style ? .on : .off
            item.target = self
            ropeMenu.addItem(item)
        }
        ropes.submenu = ropeMenu
        menu.addItem(ropes)
        menu.addItem(HangingMenus.hangFrom(store: store))
        menu.addItem(HangingMenus.breeze(store: store))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Charm", action: #selector(menuHide), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func menuLibrary() { openCustomize?(.library) }
    @objc private func menuCreate() { openCustomize?(.create) }
    @objc private func menuAppearance() { openCustomize?(.appearance) }
    @objc private func menuHide() { store.update { $0.isVisible = false } }
    @objc private func menuRope(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = RopeStyle(rawValue: raw) else { return }
        store.update { $0.ropeStyle = style }
    }

    // MARK: - Drops

    private func droppedPicture(_ info: any NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: PictureImporter.supportedTypes.map(\.identifier),
        ]
        return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }

    func canAcceptDrop(_ info: any NSDraggingInfo) -> Bool {
        guard let rope, droppedPicture(info) != nil else { return false }
        let screenPoint = info.draggingLocation
        guard let panel else { return false }
        let point = CGPoint(x: screenPoint.x, y: panel.frame.height - screenPoint.y)
        return rope.canGrab(at: point)
    }

    func acceptDrop(_ info: any NSDraggingInfo) -> Bool {
        guard let url = droppedPicture(info) else { return false }
        onImportPicture?(url)
        return true
    }
}

extension ResolvedCharm {
    /// The colour of the light under the charm.
    var glowColor: RGBA {
        switch source {
        case .custom: return RGBA(hex: 0xFFE9B0)
        case let .builtIn(definition):
            switch definition.art {
            case let .cutout(_, finish), let .medallion(_, finish, _): return finish.highlight
            case let .drawn(shape):
                switch shape {
                case .evilEye, .planet: return RGBA(hex: 0x86CBFF)
                case .fourLeafClover: return RGBA(hex: 0x9EE8B6)
                case .heart, .luckySeven: return RGBA(hex: 0xFF9C9C)
                case .crystal: return RGBA(hex: 0xC9B0FF)
                case .lotus: return RGBA(hex: 0xFFD3E0)
                default: return RGBA(hex: 0xFFE9B0)
                }
            }
        }
    }
}

/// Choosing a display by a stable key that survives reconnection.
@MainActor
enum DisplayChoice {
    static func key(for screen: NSScreen) -> String {
        let index = NSScreen.screens.firstIndex(of: screen) ?? 0
        return "\(screen.localizedName)#\(index)"
    }

    static func screen(for key: String?) -> NSScreen {
        let screens = NSScreen.screens
        if let key {
            if let exact = screens.first(where: { self.key(for: $0) == key }) { return exact }
            let name = key.split(separator: "#").first.map(String.init)
            if let byName = screens.first(where: { $0.localizedName == name }) { return byName }
        }
        return screens.first ?? NSScreen.main!
    }
}
