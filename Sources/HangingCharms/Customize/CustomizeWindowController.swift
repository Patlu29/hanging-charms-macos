import AppKit
import Observation
import SwiftUI
import HangingCharmsCore

enum CustomizePage: String, CaseIterable, Identifiable {
    case library, create, appearance, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Library"
        case .create: "Create"
        case .appearance: "Appearance"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .library: "square.grid.2x2"
        case .create: "wand.and.stars"
        case .appearance: "paintbrush"
        case .about: "info.circle"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .library: "1"
        case .create: "2"
        case .appearance: "3"
        case .about: "4"
        }
    }
}

/// Shared state between the window, its pages and the rest of the app.
@MainActor
@Observable
final class CustomizeModel {
    var page: CustomizePage = .library
    var pendingImport: URL?
    var searchFocusRequest = 0

    let store: SettingsStore
    let library: CharmLibrary
    let audio: AudioService
    let charmsChanged: () -> Void

    init(store: SettingsStore, library: CharmLibrary, audio: AudioService, charmsChanged: @escaping () -> Void) {
        self.store = store
        self.library = library
        self.audio = audio
        self.charmsChanged = charmsChanged
    }
}

/// Customize lives in an NSWindow around a hosting controller, built on open and torn
/// down on close, so a closed window holds no view tree or rendered thumbnails.
@MainActor
final class CustomizeWindowController: NSObject, NSWindowDelegate {
    let model: CustomizeModel
    private var window: NSWindow?

    init(model: CustomizeModel) {
        self.model = model
    }

    func show(_ page: CustomizePage? = nil) {
        if let page { model.page = page }
        if window == nil {
            let hosting = NSHostingController(rootView: CustomizeView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Hanging Charms"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 920, height: 640))
            window.contentMinSize = NSSize(width: 780, height: 540)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("HangingCharms.Customize")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
        CharmArtwork.clearCache()
    }
}

struct CustomizeView: View {
    @Bindable var model: CustomizeModel

    var body: some View {
        NavigationSplitView {
            List(CustomizePage.allCases, selection: Binding(get: { model.page }, set: { if let page = $0 { model.page = page } })) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            Group {
                switch model.page {
                case .library: LibraryView(model: model)
                case .create: CreateView(model: model)
                case .appearance: AppearanceView(store: model.store, audio: model.audio)
                case .about: AboutView(library: model.library)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(shortcuts)
    }

    /// Window-wide shortcuts, as invisible buttons.
    private var shortcuts: some View {
        ZStack {
            ForEach(CustomizePage.allCases) { page in
                Button(page.title) { model.page = page }
                    .keyboardShortcut(page.shortcut, modifiers: .command)
            }
            Button("Search") {
                model.page = .library
                model.searchFocusRequest += 1
            }
            .keyboardShortcut("f", modifiers: .command)
            Button("Show or Hide Charm") { model.store.update { $0.isVisible.toggle() } }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A charm drawn for SwiftUI.
struct CharmThumbnail: View {
    let charm: ResolvedCharm
    let side: CGFloat

    var body: some View {
        Image(nsImage: CharmArtwork.nsImage(for: charm, side: side))
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .accessibilityLabel(charm.name)
    }
}
