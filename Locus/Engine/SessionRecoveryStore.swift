import Foundation

enum SessionRecoveryStore {
    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("last-session.json")
    }
    static var needsRestore: Bool {
        get { UserDefaults.standard.bool(forKey: "locus.needsRestore") }
        set { UserDefaults.standard.set(newValue, forKey: "locus.needsRestore") }
    }
    static func load() -> SessionCheckpoint? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20 * 1024 * 1024,
              let data = try? Data(contentsOf: file), let record = try? JSONDecoder().decode(SessionCheckpoint.self, from: data), record.isValid else { return nil }
        return record
    }
    static func save(_ record: SessionCheckpoint) throws {
        guard record.isValid else { throw RouteError.invalid }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(record)
        guard data.count <= 20 * 1024 * 1024 else { throw RouteError.tooLarge }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func remove() { try? FileManager.default.removeItem(at: file) }
}
