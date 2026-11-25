import AppKit
import SwiftUI
import HangingCharmsCore

struct AppearanceView: View {
    @Bindable var store: SettingsStore
    let audio: AudioService

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in store.update { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        Form {
            Section("Rope") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(RopeStyle.allCases) { style in
                        ropeTile(style)
                    }
                }
                .padding(.vertical, 4)
                Text(store.settings.ropeStyle.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Elastic", isOn: binding(\.elastic))
                    .help("The cord gives when it is pulled, up to half again its length.")
            }

            Section("Size and position") {
                slider("Rope length", value: binding(\.ropeLength), in: AppSettings.ropeLengthRange, format: "%.0f%%", scale: 100)
                slider("Charm size", value: binding(\.charmSize), in: AppSettings.charmSizeRange, format: "%.0f%%", scale: 100)
                slider("Across the screen", value: binding(\.horizontalPosition), in: 0...1, format: "%.0f%%", scale: 100)
                slider("Opacity", value: binding(\.opacity), in: AppSettings.opacityRange, format: "%.0f%%", scale: 100)
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

            Section("Motion") {
                Toggle("Moves when the pointer brushes it", isOn: binding(\.mouseReactive))
                Toggle("Swing changes with the time of day", isOn: binding(\.timeOfDay))
                    .help("Mornings swing longer and wider; nights settle sooner.")
                Toggle("Reduce motion", isOn: binding(\.reduceMotion))
                    .help("The charm hangs still and moves only when you move it.")
            }

            Section("Mood") {
                Toggle("Glow under the charm", isOn: binding(\.glow))
                Toggle("Charm sounds", isOn: binding(\.sounds))
                HStack {
                    slider("Volume", value: binding(\.volume), in: AppSettings.volumeRange, format: "%.0f%%", scale: 100)
                    Button("Test") { audio.play(.bell, intensity: 0.8) }
                }
                .disabled(!store.settings.sounds)
            }

            Section("System") {
                Toggle("Hide while an app is full screen", isOn: binding(\.hideInFullScreen))
                Toggle("Open at login", isOn: binding(\.launchAtLogin))
                LabeledContent("Show or hide from anywhere", value: GlobalHotKey.displayString)
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
        .formStyle(.grouped)
    }

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
        .onTapGesture { store.update { $0.ropeStyle = style } }
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
                    .frame(width: 48, alignment: .trailing)
            }
        }
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
                    .frame(maxWidth: 460)
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
