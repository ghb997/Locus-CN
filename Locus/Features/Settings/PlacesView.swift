import SwiftUI

struct PlacesView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedGroup = ""
    @State private var editing: SavedPlace?
    @State private var selected: SavedPlace?
    private var groups: [String] { Array(Set(library.favorites.compactMap(\.group).filter { !$0.isEmpty })).sorted() }
    private func filtered(_ places: [SavedPlace], grouped: Bool = false) -> [SavedPlace] {
        places.filter {
            (!grouped || selectedGroup.isEmpty || $0.group == selectedGroup) &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || ($0.group ?? "").localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                if !groups.isEmpty {
                    Picker(L10n.tr("Group"), selection: $selectedGroup) {
                        Text(L10n.tr("All groups")).tag("")
                        ForEach(groups, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section(L10n.tr("Favorites")) {
                    if library.favorites.isEmpty { Text(L10n.tr("Star a pin from the map to save it.")).foregroundStyle(.secondary) }
                    ForEach(filtered(library.favorites, grouped: true)) { place in
                        row(place)
                            .swipeActions {
                                Button(L10n.tr("Delete"), role: .destructive) { library.deleteFavorite(place) }
                                Button(L10n.tr("Edit")) { editing = place }.tint(.blue)
                            }
                    }
                }
                Section(L10n.tr("Search history")) {
                    ForEach(filtered(library.searches)) { place in
                        row(place).swipeActions { Button(L10n.tr("Delete"), role: .destructive) { library.deleteRecent(place, search: true) } }
                    }
                }
                Section(L10n.tr("Successful teleports")) {
                    ForEach(filtered(library.recents)) { place in
                        row(place).swipeActions { Button(L10n.tr("Delete"), role: .destructive) { library.deleteRecent(place) } }
                    }
                }
            }
            .searchable(text: $query, prompt: L10n.tr("Search places"))
            .navigationTitle(L10n.tr("Places"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("Done")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) { NavigationLink { LibraryBackupView() } label: { Image(systemName: "square.and.arrow.up").accessibilityLabel(L10n.tr("Library backup")) } }
            }
            .sheet(item: $editing) { place in FavoriteEditor(place: place) { library.updateFavorite($0) } }
            .confirmationDialog(selected?.name ?? "", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
                if let place = selected {
                    Button(L10n.tr("Use location")) { session.pin = place.coordinate; dismiss() }
                    Button(L10n.tr("Teleport")) { session.teleport(to: place.coordinate, pairing: pairing, name: place.name); dismiss() }
                    Button(L10n.tr("Save favorite")) { library.addFavorite(place) }
                    Button(L10n.tr("Cancel"), role: .cancel) { selected = nil }
                }
            }
        }
    }
    private func row(_ place: SavedPlace) -> some View {
        Button { selected = place } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).foregroundStyle(.primary)
                if let group = place.group, !group.isEmpty { Text(group).font(.caption).foregroundStyle(.secondary) }
                Text(CoordinateConverter.label(place.coordinate)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}

private struct FavoriteEditor: View {
    @State var place: SavedPlace
    let onSave: (SavedPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.tr("Name"), text: $place.name)
                TextField(L10n.tr("Group"), text: Binding(get: { place.group ?? "" }, set: { place.group = $0 }))
            }
            .navigationTitle(L10n.tr("Edit favorite"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("Save")) { onSave(place); dismiss() }.disabled(!place.isValid) }
            }
        }
    }
}
