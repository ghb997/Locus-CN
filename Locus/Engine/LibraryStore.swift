import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var archive = LibraryArchive()
    @Published var draft = SavedRoute() { didSet { scheduleSave() } }
    @Published var lastError: String?
    @Published var incomingGPX: URL?
    private var saveTask: Task<Void, Never>?
    private var loading = true
    private var needsRecovery = false
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("library-v1.json") }
    var favorites: [SavedPlace] { archive.favorites }
    var routes: [SavedRoute] { archive.routes }
    var recents: [SavedPlace] { archive.recents }
    var searches: [SavedPlace] { archive.searches }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Library", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                archive = try LibraryArchive.decode(Data(contentsOf: file))
            } else {
                archive.favorites = SavedPlace.load(key: "locus.favorites")
                archive.recents = SavedPlace.load(key: "locus.recents")
            }
            draft = archive.draft
        } catch { needsRecovery = true; lastError = L10n.tr("The saved library could not be read. Import a valid backup to recover it; the original file has been preserved.") }
        loading = false
    }
    private func write(_ value: LibraryArchive) throws {
        let data = try value.encoded()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func commit(_ value: LibraryArchive) throws {
        guard !needsRecovery else { throw ArchiveError.invalid }
        try write(value); archive = value
    }
    private func scheduleSave() {
        guard !loading else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.flush()
        }
    }
    func flush() {
        saveTask?.cancel(); saveTask = nil
        guard !loading, !needsRecovery else { return }
        do { var next = archive; next.draft = draft; try commit(next) }
        catch { lastError = error.localizedDescription }
    }
    func addFavorite(_ place: SavedPlace) {
        var next = archive
        next.favorites.removeAll { $0.id == place.id }; next.favorites.insert(place, at: 0)
        update(next)
    }
    func updateFavorite(_ place: SavedPlace) { addFavorite(place) }
    func deleteFavorite(_ place: SavedPlace) { var next = archive; next.favorites.removeAll { $0.id == place.id }; update(next) }
    func record(_ place: SavedPlace, search: Bool) {
        var next = archive
        var items = search ? next.searches : next.recents
        items.removeAll { $0.id == place.id }; items.insert(place, at: 0); items = Array(items.prefix(50))
        if search { next.searches = items } else { next.recents = items }
        update(next)
    }
    func deleteRecent(_ place: SavedPlace, search: Bool = false) {
        var next = archive
        if search { next.searches.removeAll { $0.id == place.id } } else { next.recents.removeAll { $0.id == place.id } }
        update(next)
    }
    func saveDraft() throws {
        guard draft.playbackPoints.count >= 2 else { throw RouteError.invalid }
        _ = try RouteTimeline(route: draft)
        var value = draft; value.updatedAt = Date()
        if value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value.name = L10n.tr("Untitled route") }
        var next = archive
        next.routes.removeAll { $0.id == value.id }; next.routes.insert(value, at: 0); next.draft = value
        try commit(next); draft = value
    }
    func deleteRoute(_ route: SavedRoute) { var next = archive; next.routes.removeAll { $0.id == route.id }; update(next) }
    func exportBackup() throws -> URL {
        var value = archive; value.draft = draft
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Locus-Backup-\(UUID().uuidString).json")
        try value.encoded().write(to: url, options: .atomic)
        return url
    }
    func importBackup(_ data: Data, policy: MergePolicy) throws {
        let incoming = try LibraryArchive.decode(data)
        let next = needsRecovery ? incoming : try archive.merging(incoming, policy: policy)
        try write(next)
        needsRecovery = false; archive = next; draft = next.draft; lastError = nil
    }
    private func update(_ value: LibraryArchive) {
        do { var next = value; next.draft = draft; try commit(next) } catch { lastError = error.localizedDescription }
    }
}
