import SwiftUI
import HangingCharmsCore

private enum LibraryFilter: Hashable, Identifiable {
    case all, favourites, recents, mine
    case collection(CharmCollection)

    var id: String {
        switch self {
        case .all: "all"
        case .favourites: "favourites"
        case .recents: "recents"
        case .mine: "mine"
        case let .collection(collection): collection.rawValue
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .favourites: "Favourites"
        case .recents: "Recent"
        case .mine: "My Charms"
        case let .collection(collection): collection.displayName
        }
    }

    static var everything: [LibraryFilter] {
        [.all, .favourites, .recents, .mine] + CharmCollection.allCases.map(LibraryFilter.collection)
    }
}

struct LibraryView: View {
    @Bindable var model: CustomizeModel
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var selection: String?
    @State private var ropeSelection: Int?
    @FocusState private var searchFocused: Bool

    private var settings: AppSettings { model.store.settings }

    private var visibleIDs: [String] {
        let builtIn = CharmCatalog.search(query).map(\.id)
        let custom = model.library.customCharms
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .map(\.charmID)
        switch filter {
        case .all: return custom + builtIn
        case .mine: return custom
        case .favourites: return settings.favourites.filter { (custom + builtIn).contains($0) }
        case .recents: return settings.recents.filter { (custom + builtIn).contains($0) }
        case let .collection(collection):
            let ids = Set(CharmCatalog.charms(in: collection).map(\.id))
            return builtIn.filter(ids.contains)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider()
                grid
                Divider()
                ropeStrip
            }
            Divider()
            detail
                .frame(width: 270)
        }
        .background(libraryShortcuts)
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
        .onAppear {
            if selection == nil { selection = settings.charmIDs.last }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search charms", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(LibraryFilter.everything) { item in
                        Button(item.title) { filter = item }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(filter == item ? Color.accentColor : Color.secondary.opacity(0.12)))
                            .foregroundStyle(filter == item ? Color.white : Color.primary)
                    }
                }
            }
        }
        .padding(14)
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            if visibleIDs.isEmpty {
                ContentUnavailableView(
                    filter == .mine ? "No charms of your own yet" : "No charms found",
                    systemImage: filter == .mine ? "wand.and.stars" : "magnifyingglass",
                    description: Text(filter == .mine ? "Use Create to make one from a photo." : "Try another search.")
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(visibleIDs, id: \.self) { id in
                        if let charm = model.library.resolve(id) {
                            tile(charm)
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private func tile(_ charm: ResolvedCharm) -> some View {
        let selected = selection == charm.id
        let onRope = settings.charmIDs.contains(charm.id)
        return VStack(spacing: 6) {
            CharmThumbnail(charm: charm, side: 66)
            Text(charm.name)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if settings.favourites.contains(charm.id) {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).padding(6)
            }
        }
        .overlay(alignment: .topLeading) {
            if onRope {
                Image(systemName: "link").font(.caption2).foregroundStyle(.secondary).padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { hang(charm.id, adding: false) }
        .onTapGesture { selection = charm.id }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let charm = model.library.resolve(id) {
            ScrollView {
                VStack(spacing: 14) {
                    CharmThumbnail(charm: charm, side: 170)
                        .padding(.top, 20)
                    VStack(spacing: 4) {
                        Text(charm.name).font(.title2.weight(.semibold))
                        Text(charm.collectionName).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(charm.detail)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        Button { hang(id, adding: false) } label: {
                            Label("Hang This Charm", systemImage: "arrow.down.to.line").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button { hang(id, adding: true) } label: {
                            Label(settings.charmIDs.count >= CharmStackLayout.maximumCharms ? "Swap Into Bottom of Rope" : "Add to Rope",
                                  systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        Button { model.store.update { $0.toggleFavourite(id) } } label: {
                            Label(settings.favourites.contains(id) ? "Remove Favourite" : "Favourite",
                                  systemImage: settings.favourites.contains(id) ? "star.slash" : "star").frame(maxWidth: .infinity)
                        }
                        if charm.isCustom {
                            Button(role: .destructive) {
                                model.library.deleteCustom(id)
                                model.charmsChanged()
                                selection = nil
                            } label: {
                                Label("Delete Charm", systemImage: "trash").frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .controlSize(.large)
                    Text("Weight \(charm.metrics.mass, specifier: "%.1f") · Sounds like \(charm.sound.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(18)
            }
        } else {
            ContentUnavailableView("Choose a charm", systemImage: "hand.tap", description: Text("Select a charm to see it here."))
        }
    }

    // MARK: - Rope strip

    private var ropeStrip: some View {
        HStack(spacing: 10) {
            Text("On the rope")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(settings.charmIDs.enumerated()), id: \.offset) { index, id in
                let charm = model.library.resolveOrDefault(id)
                HStack(spacing: 4) {
                    CharmThumbnail(charm: charm, side: 30)
                    if settings.charmIDs.count < 3 { Text(charm.name).font(.caption).lineLimit(1) }
                    if settings.charmIDs.count > 1 {
                        Button { model.store.update { $0.removeCharm(at: index) } } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Take this charm off the rope")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(ropeSelection == index ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08)))
                .onTapGesture {
                    ropeSelection = index
                    selection = id
                }
                if index < settings.charmIDs.count - 1 {
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text("⌥↑ ⌥↓ to reorder")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func hang(_ id: String, adding: Bool) {
        model.store.update { $0.hang(id, adding: adding) }
        ropeSelection = adding ? model.store.settings.charmIDs.count - 1 : 0
    }

    private func moveRopeCharm(_ offset: Int) {
        guard let index = ropeSelection else { return }
        model.store.update { $0.moveCharm(at: index, by: offset) }
        let target = index + offset
        if model.store.settings.charmIDs.indices.contains(target) { ropeSelection = target }
    }

    private var libraryShortcuts: some View {
        ZStack {
            Button("Favourite") {
                if let selection { model.store.update { $0.toggleFavourite(selection) } }
            }
            .keyboardShortcut("d", modifiers: .command)
            Button("Move Up") { moveRopeCharm(-1) }
                .keyboardShortcut(.upArrow, modifiers: .option)
            Button("Move Down") { moveRopeCharm(1) }
                .keyboardShortcut(.downArrow, modifiers: .option)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
