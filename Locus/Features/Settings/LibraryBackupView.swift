import SwiftUI
import UniformTypeIdentifiers

struct LibraryBackupView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var shared: SharedFile?
    @State private var showImporter = false
    @State private var pending: Data?
    @State private var preview = ""
    @State private var error: String?
    @State private var result: String?
    var body: some View {
        List {
            Section {
                Button(L10n.tr("Export library backup")) {
                    do { shared = SharedFile(url: try library.exportBackup()) } catch { self.error = error.localizedDescription }
                }
                Button(L10n.tr("Import library backup")) { showImporter = true }
            } footer: {
                Text(L10n.tr("Backups contain places, route drafts, saved routes and history. They never contain pairing keys. Imports merge favorites by coordinate and routes by ID; current history and draft are kept."))
            }
            if let result { Text(result).foregroundStyle(.secondary) }
        }
        .navigationTitle(L10n.tr("Library backup"))
        .sheet(item: $shared) { FileShareSheet(url: $0.url) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20 * 1024 * 1024 else { throw RouteError.tooLarge }
                let data = try Data(contentsOf: url), archive = try LibraryArchive.decode(data)
                preview = L10n.format("Import %d favorites and %d routes?", archive.favorites.count, archive.routes.count)
                pending = data
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog(preview, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            ForEach(MergePolicy.allCases) { policy in
                Button(policy.title) {
                    guard let data = pending else { return }
                    do { try library.importBackup(data, policy: policy); result = L10n.tr("Library backup imported.") } catch { self.error = error.localizedDescription }
                    pending = nil
                }
            }
            Button(L10n.tr("Cancel"), role: .cancel) { pending = nil }
        }
        .alert("Locus", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L10n.tr("OK"), role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}
