import AppKit
import SwiftUI
import UniformTypeIdentifiers
import HangingCharmsCore

struct CreateView: View {
    @Bindable var model: CustomizeModel
    @State private var source: CGImage?
    @State private var result: CGImage?
    @State private var name = "My Charm"
    @State private var cutOut = true
    @State private var working = false
    @State private var message: String?
    @State private var dropTargeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Make a charm from a picture")
                    .font(.title2.weight(.semibold))
                // No .fixedSize here: forcing this paragraph to its full height left the
                // whole Customize window blank on this page. It wraps without it.
                Text("Drop a photo or picture here, or on the charm itself. The subject is cut out on this Mac with Apple's Vision framework; nothing is uploaded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                dropZone

                Toggle("Cut out the subject", isOn: $cutOut)
                    .onChange(of: cutOut) { Task { await process() } }
                HStack {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button("Save and Hang") { save(hang: true) }
                        .buttonStyle(.borderedProminent)
                        .disabled(result == nil || working)
                    Button("Save to Library") { save(hang: false) }
                        .disabled(result == nil || working)
                }
                .controlSize(.large)
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("My Charms").font(.headline)
                if model.library.customCharms.isEmpty {
                    Text("Charms you make appear here.").font(.callout).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.library.customCharms) { record in
                            if let charm = model.library.resolve(record.charmID) {
                                HStack {
                                    CharmThumbnail(charm: charm, side: 40)
                                    Text(record.name).lineLimit(1)
                                    Spacer()
                                    Button { model.store.update { $0.hang(record.charmID, adding: false) } } label: {
                                        Image(systemName: "arrow.down.to.line")
                                    }
                                    .help("Hang this charm")
                                    Button(role: .destructive) {
                                        model.library.deleteCustom(record.charmID)
                                        model.charmsChanged()
                                    } label: { Image(systemName: "trash") }
                                    .help("Delete this charm")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(width: 270)
        }
        .task(id: model.pendingImport) {
            if let url = model.pendingImport {
                model.pendingImport = nil
                await load(url)
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(dropTargeted ? 0.12 : 0.05)))
            if working {
                ProgressView("Cutting out…")
            } else if let result {
                CharmThumbnail(
                    charm: ResolvedCharm(id: "preview-\(result.hashValue)", name: name, detail: "", collectionName: "",
                                         metrics: .default, sound: .glass, source: .custom(result)),
                    side: 210
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Drop a PNG, JPEG, HEIC, WebP or SVG").foregroundStyle(.secondary)
                    Button("Choose Picture…", action: choose)
                }
            }
        }
        .frame(height: 260)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await load(url) }
            }
            return true
        }
        .contextMenu {
            Button("Choose Picture…", action: choose)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PictureImporter.supportedTypes
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture to make into a charm"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await load(url) }
        }
    }

    private func load(_ url: URL) async {
        do {
            source = try PictureImporter.load(url)
            name = PictureImporter.suggestedName(for: url)
            message = nil
            await process()
        } catch {
            message = error.localizedDescription
        }
    }

    private func process() async {
        guard let source else { return }
        working = true
        defer { working = false }
        var image = source
        if cutOut {
            if let subject = await PictureImporter.cutOutSubject(source) {
                image = subject
                message = nil
            } else {
                message = "No clear subject found, so the whole picture is used."
            }
        }
        result = (try? PictureImporter.finish(image)) ?? image
    }

    private func save(hang: Bool) {
        guard let result else { return }
        do {
            let id = try model.library.addCustom(image: result, name: name)
            if hang { model.store.update { $0.hang(id, adding: false) } }
            model.charmsChanged()
            message = hang ? "Saved and hung on the rope." : "Saved to your Library."
            self.result = nil
            self.source = nil
        } catch {
            message = "Could not save the charm: \(error.localizedDescription)"
        }
    }
}
