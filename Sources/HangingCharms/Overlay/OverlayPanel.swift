import AppKit
import HangingCharmsCore

/// A borderless, transparent, non-activating panel over a whole display.
///
/// It ignores the mouse everywhere until the cursor is over a charm, at which point the
/// controller lets it take the mouse so the charm can be picked up. It never becomes key,
/// so grabbing a charm never takes focus away from the app you are using.
final class OverlayPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // While the panel holds the mouse (pointer over a charm), mouse-moved events go
        // to this window, not to other apps, so it must accept them; otherwise hover
        // tracking stops the moment the pointer reaches a charm.
        acceptsMouseMovedEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setLevel(.aboveAll)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setLevel(_ level: OverlayLevel) {
        switch level {
        case .aboveAll:
            self.level = .statusBar
        case .desktop:
            self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }
}

/// The overlay's content: a layer tree, and the mouse and drop events for the charm.
final class OverlayView: NSView {
    weak var controller: OverlayController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        controller?.mouseDown(event)
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.mouseDragged(event)
    }

    override func mouseUp(with event: NSEvent) {
        controller?.mouseUp(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.showContextMenu(for: event, in: self)
    }

    // MARK: - Dropping a picture on the charm

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.canAcceptDrop(sender) == true ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.canAcceptDrop(sender) == true ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        controller?.acceptDrop(sender) ?? false
    }
}
