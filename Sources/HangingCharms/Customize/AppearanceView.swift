import AppKit
import SwiftUI
import HangingCharmsCore

enum AppearanceTab: String, CaseIterable, Identifiable {
    case rope, hooks, hanging, light, charms, motion, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rope: "Rope"
        case .hooks: "Hooks"
        case .hanging: "Hanging"
        case .light: "Light"
        case .charms: "Charms"
        case .motion: "Motion"
        case .system: "System"
        }
    }
}

struct AppearanceView: View {
    @Bindable var store: SettingsStore
    let library: CharmLibrary
    let audio: AudioService
    @State private var tab: AppearanceTab = AppearanceView.startTab

    /// The tab a fresh Appearance page opens on. The diagnostic renderer sets it.
    static var startTab: AppearanceTab = .rope

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in store.update { $0[keyPath: keyPath] = value } })
    }

    private func colour(_ keyPath: WritableKeyPath<AppSettings, RGBA>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: store.settings[keyPath: keyPath].ns) },
            set: { colour in store.update { $0[keyPath: keyPath] = RGBA(NSColor(colour)) } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(AppearanceTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 620)
            .padding(.top, 14)
            .padding(.horizontal, 20)

            Form {
                switch tab {
                case .rope: ropeSections
                case .hooks: hookSections
                case .hanging: hangingSections
                case .light: lightSections
                case .charms: charmSections
                case .motion: motionSections
                case .system: systemSections
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Rope

    @ViewBuilder
    private var ropeSections: some View {
        Section("Style") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(RopeStyle.allCases) { style in
                    ropeTile(style)
                }
            }
            .padding(.vertical, 4)
            Text(store.settings.ropeStyle.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Section("Chain and cord") {
            Picker("Pattern", selection: binding(\.ropePattern)) {
                Text("The style's own").tag(RopeAppearance.Pattern?.none)
                Divider()
                ForEach(RopeAppearance.Pattern.allCases) { Text($0.displayName).tag(RopeAppearance.Pattern?.some($0)) }
            }
            slider("Thread thickness", value: binding(\.ropeThickness), in: AppSettings.ropeThicknessRange, format: "%.0f%%", scale: 100)
                .help("From a quarter of the style's width up to six times it.")
            slider("Link and twist size", value: binding(\.linkSize), in: AppSettings.linkSizeRange, format: "%.0f%%", scale: 100)
                .help("How long each chain link or twist of the cord is.")
            Toggle("Custom colours", isOn: binding(\.customRopeColors))
            if store.settings.customRopeColors {
                ColorPicker("Main colour", selection: colour(\.ropePrimary), supportsOpacity: false)
                ColorPicker("Detail colour", selection: colour(\.ropeSecondary), supportsOpacity: false)
                HStack {
                    Spacer()
                    Button("Use the style's colours") {
                        store.update {
                            $0.ropePrimary = $0.ropeStyle.appearance.primary
                            $0.ropeSecondary = $0.ropeStyle.appearance.secondary
                        }
                    }
                }
            }
            slider("Rope length", value: binding(\.ropeLength), in: AppSettings.ropeLengthRange, format: "%.0f%%", scale: 100)
            Toggle("Elastic", isOn: binding(\.elastic))
                .help("The cord gives when it is pulled, up to half again its length.")
        }

        Section("Beads") {
            Picker("Beads on the rope", selection: binding(\.beads)) {
                ForEach(BeadDensity.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Group {
                ColorPicker("Bead colour", selection: colour(\.beadColor), supportsOpacity: false)
                slider("Bead size", value: binding(\.beadSize), in: AppSettings.beadSizeRange, format: "%.1f×", scale: 1)
            }
            .disabled(store.settings.beads == .none)
        }
    }

    // MARK: - Hanging

    @ViewBuilder
    private var hangingSections: some View {
        Section("Hang from") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(HangPoint.allCases) { point in
                    let symbol = switch point {
                    case .menuBar: "menubar.rectangle"
                    case .notch: "laptopcomputer"
                    case .frontWindow: "macwindow"
                    case .anywhere: "hand.point.up.left"
                    }
                    attachmentTile(title: point.displayName, selected: store.settings.hangPoint == point,
                                   image: NSImage(systemSymbolName: symbol, accessibilityDescription: point.displayName)?
                                       .withSymbolConfiguration(.init(pointSize: 26, weight: .regular))) {
                        store.update { $0.hangPoint = point }
                    }
                }
            }
            .padding(.vertical, 4)
            Text(store.settings.hangPoint.summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            switch store.settings.hangPoint {
            case .menuBar:
                slider("Across the screen", value: binding(\.horizontalPosition), in: 0...1, format: "%.0f%%", scale: 100)
                slider("Hang below the menu bar", value: binding(\.hangDrop), in: AppSettings.hangDropRange, format: "%.0f pt", scale: 1)
            case .notch:
                slider("Hang below the notch", value: binding(\.hangDrop), in: AppSettings.hangDropRange, format: "%.0f pt", scale: 1)
            case .frontWindow:
                slider("Across the window", value: binding(\.horizontalPosition), in: 0...1, format: "%.0f%%", scale: 100)
            case .anywhere:
                slider("Across", value: binding(\.pinX), in: 0...1, format: "%.0f%%", scale: 100)
                slider("Down", value: binding(\.pinY), in: 0...0.9, format: "%.0f%%", scale: 100)
            }
            Text("Tip: drag the top of the rope to hang it anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Breeze") {
            Picker("Breeze", selection: binding(\.breeze)) {
                ForEach(Breeze.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(store.settings.breeze == .still
                 ? "The charm moves only when something moves it, and costs nothing while it rests."
                 : "The charm sways on its own. It never fully rests, so it uses a little more power.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Section("Screen") {
            Picker("Display", selection: Binding(
                get: { store.settings.displayKey ?? "" },
                set: { value in store.update { $0.displayKey = value.isEmpty ? nil : value } }
            )) {
                Text("Main display").tag("")
                ForEach(NSScreen.screens, id: \.self) { screen in
                    Text(screen.localizedName).tag(DisplayChoice.key(for: screen))
                }
            }
            Picker("Window", selection: binding(\.level)) {
                ForEach(OverlayLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
    }

    // MARK: - Hooks

    @ViewBuilder
    private var hookSections: some View {
        Section("Top of the rope") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(GrappleStyle.allCases) { style in
                    attachmentTile(title: style.displayName, selected: store.settings.grappleStyle == style,
                                   image: grapplePreview(style)) {
                        store.update { $0.grappleStyle = style }
                    }
                }
            }
            .padding(.vertical, 4)
            Group {
                Picker("Finish", selection: binding(\.grappleFinish)) {
                    ForEach(AttachmentFinish.allCases) { Text($0.displayName).tag($0) }
                }
                slider("Size", value: binding(\.grappleSize), in: AppSettings.grappleSizeRange, format: "%.0f%%", scale: 100)
            }
            .disabled(store.settings.grappleStyle == .none)
        }

        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(HookStyle.allCases) { style in
                    attachmentTile(title: style.displayName, selected: store.settings.hookStyle == style,
                                   image: hookPreview(style)) {
                        store.update { $0.hookStyle = style }
                    }
                }
            }
            .padding(.vertical, 4)
            Picker("Finish", selection: binding(\.hookFinish)) {
                ForEach(AttachmentFinish.allCases) { Text($0.displayName).tag($0) }
            }
            slider("Size", value: binding(\.hookSize), in: AppSettings.hookSizeRange, format: "%.0f%%", scale: 100)
        } header: {
            Text("Where each charm hangs")
        } footer: {
            Text("A tied knot uses no metal at all: the cord runs straight into the charm.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func hookPreview(_ style: HookStyle) -> NSImage? {
        var settings = store.settings
        settings.hookStyle = style
        settings.hookSize = 1
        guard let image = AttachmentArtwork.connectorPreview(Connector.from(settings), pixels: 120) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 60, height: 60))
    }

    private func grapplePreview(_ style: GrappleStyle) -> NSImage? {
        let palette = store.settings.grappleFinish.palette(rope: store.settings.resolvedRopeAppearance)
        guard let image = AttachmentArtwork.grappleImage(style, base: palette.base, highlight: palette.highlight,
                                                         shadow: palette.shadow, pixels: 120) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 60, height: 60))
    }

    private func attachmentTile(title: String, selected: Bool, image: NSImage?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high)
                } else {
                    Image(systemName: "nosign").font(.title2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 52, height: 52)
            Text(title).font(.caption).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Light

    @ViewBuilder
    private var lightSections: some View {
        Section("Glow under the charm") {
            Toggle("Glow", isOn: binding(\.glow))
            Group {
                Toggle("Match the charm's colour", isOn: Binding(
                    get: { !store.settings.customGlowColor },
                    set: { match in store.update { $0.customGlowColor = !match } }
                ))
                if store.settings.customGlowColor {
                    ColorPicker("Glow colour", selection: colour(\.glowColor), supportsOpacity: false)
                }
                slider("Brightness", value: binding(\.glowIntensity), in: AppSettings.glowIntensityRange, format: "%.0f%%", scale: 100)
                slider("Size", value: binding(\.glowSize), in: AppSettings.glowSizeRange, format: "%.0f%%", scale: 100)
                Toggle("Breathe slowly", isOn: binding(\.glowBreathing))
            }
            .disabled(!store.settings.glow)
        }
        Section("Light on the rope") {
            Toggle("Glow along the cord", isOn: binding(\.ropeGlow))
                .help("A soft halo in the cord's main colour. The neon style always has one.")
        }
        Section("Window") {
            slider("Opacity", value: binding(\.opacity), in: AppSettings.opacityRange, format: "%.0f%%", scale: 100)
        }
    }

    // MARK: - Charms

    @ViewBuilder
    private var charmSections: some View {
        Section("All charms") {
            slider("Charm size", value: binding(\.charmSize), in: AppSettings.charmSizeRange, format: "%.0f%%", scale: 100)
            Toggle("Drop shadow", isOn: binding(\.charmShadow))
        }
        Section {
            ForEach(Array(store.settings.charmIDs.enumerated()), id: \.offset) { _, id in
                let charm = library.resolveOrDefault(id)
                LabeledContent {
                    HStack {
                        Slider(value: Binding(
                            get: { store.settings.scale(for: id) },
                            set: { value in store.update { $0.setScale(value, for: id) } }
                        ), in: AppSettings.charmScaleRange)
                        Text(String(format: "%.0f%%", store.settings.scale(for: id) * 100))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                } label: {
                    HStack(spacing: 8) {
                        CharmThumbnail(charm: charm, side: 28)
                        Text(charm.name)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Reset Sizes") {
                    store.update { settings in settings.charmIDs.forEach { settings.setScale(1, for: $0) } }
                }
                .disabled(store.settings.charmIDs.allSatisfy { store.settings.scale(for: $0) == 1 })
            }
        } header: {
            Text("Each charm on the rope")
        } footer: {
            Text("A larger charm is heavier too, so it swings like a bigger piece of metal.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Motion

    @ViewBuilder
    private var motionSections: some View {
        Section("Feel") {
            slider("Swing weight", value: binding(\.swingWeight), in: AppSettings.swingWeightRange, format: "%.0f%%", scale: 100)
                .help("Higher feels heavier and swings faster.")
            slider("Settle speed", value: binding(\.settleSpeed), in: AppSettings.settleSpeedRange, format: "%.0f%%", scale: 100)
                .help("Higher comes to rest sooner.")
            Toggle("Moves when the pointer brushes it", isOn: binding(\.mouseReactive))
            Toggle("Swing changes with the time of day", isOn: binding(\.timeOfDay))
                .help("Mornings swing longer and wider; nights settle sooner.")
            Toggle("Reduce motion", isOn: binding(\.reduceMotion))
                .help("The charm hangs still and moves only when you move it.")
        }
        Section("Sound") {
            Toggle("Charm sounds", isOn: binding(\.sounds))
            HStack {
                slider("Volume", value: binding(\.volume), in: AppSettings.volumeRange, format: "%.0f%%", scale: 100)
                Button("Test") { audio.play(.bell, intensity: 0.8) }
            }
            .disabled(!store.settings.sounds)
        }
    }

    // MARK: - System

    @ViewBuilder
    private var systemSections: some View {
        Section("System") {
            Toggle("Hide while an app is full screen", isOn: binding(\.hideInFullScreen))
            Toggle("Open at login", isOn: binding(\.launchAtLogin))
            LabeledContent("Show or hide from anywhere", value: GlobalHotKey.displayString)
        }
        Section {
            HStack {
                Spacer()
                Button("Reset All Settings…", role: .destructive) {
                    let alert = NSAlert()
                    alert.messageText = "Reset all settings?"
                    alert.informativeText = "Your rope, charms, favourites and appearance go back to how they started. Your own charms stay in the Library."
                    alert.addButton(withTitle: "Reset")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn { store.reset() }
                }
            }
        }
    }

    // MARK: - Pieces

    private func ropeTile(_ style: RopeStyle) -> some View {
        let look = style.appearance
        let selected = store.settings.ropeStyle == style
        return HStack(spacing: 10) {
            ZStack {
                Capsule().fill(Color(nsColor: look.primary.ns)).frame(width: 6, height: 34)
                Capsule().fill(Color(nsColor: look.secondary.ns)).frame(width: 2, height: 34)
            }
            .frame(width: 18)
            Text(style.displayName)
                .font(.callout)
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            store.update {
                $0.ropeStyle = style
                // Picking a new style starts its custom colours from that style.
                if !$0.customRopeColors {
                    $0.ropePrimary = style.appearance.primary
                    $0.ropeSecondary = style.appearance.secondary
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: String, scale: Double) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(String(format: format, value.wrappedValue * scale))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

extension RGBA {
    /// From any NSColor, converted to sRGB.
    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .white
        self.init(Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent), Double(srgb.alphaComponent))
    }
}

struct AboutView: View {
    let library: CharmLibrary

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "dev"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CharmThumbnail(charm: library.resolveOrDefault(CharmCatalog.defaultID), side: 120)
                    .padding(.top, 30)
                Text("Hanging Charms").font(.largeTitle.weight(.semibold))
                Text(version).foregroundStyle(.secondary)
                Text("Charms hang from a rope on your desktop. Push one and it swings, with the weight and settle of a real one.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow { Text("Physics").foregroundStyle(.secondary); Text("Verlet rope, 20 segments, fixed 240 Hz") }
                    GridRow { Text("Charms").foregroundStyle(.secondary); Text("\(CharmCatalog.all.count) built in, \(CharmCollection.allCases.count) collections, plus your own") }
                    GridRow { Text("Privacy").foregroundStyle(.secondary); Text("No network, no analytics, no permissions") }
                    GridRow { Text("Licence").foregroundStyle(.secondary); Text("MIT. All charm artwork is original.") }
                }
                .font(.callout)
                .padding(.top, 6)
                Text("The rope solver's design follows the one documented in the MIT-licensed Hangly for Windows project by sharancreatedthis. Hanging Charms is an independent macOS app and uses none of Hangly's artwork, name or branding.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .padding(.top, 10)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
