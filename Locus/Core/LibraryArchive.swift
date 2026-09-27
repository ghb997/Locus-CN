import Foundation

enum MergePolicy: String, CaseIterable, Identifiable {
    case keepExisting, replaceMatching
    var id: String { rawValue }
    var title: String { self == .keepExisting ? L10n.tr("Keep existing items") : L10n.tr("Replace matching items") }
}

struct LibraryArchive: Codable {
    var schemaVersion = 1
    var coordinateSystem = CoordinateSystem.wgs84
    var favorites: [SavedPlace] = []
    var routes: [SavedRoute] = []
    var recents: [SavedPlace] = []
    var searches: [SavedPlace] = []
    var draft = SavedRoute()

    func validate() throws {
        guard schemaVersion == 1, coordinateSystem == .wgs84 else { throw ArchiveError.unsupported }
        guard favorites.count <= 5000, routes.count <= 200, recents.count <= 100, searches.count <= 100,
              routes.reduce(draft.path.count + draft.waypoints.count, { $0 + $1.path.count + $1.waypoints.count }) <= 200_000 else { throw RouteError.tooLarge }
        guard (favorites + recents + searches).allSatisfy(\.isValid), routes.allSatisfy(\.isValid), draft.isValid,
              Set(routes.map(\.id)).count == routes.count, Set(favorites.map(\.id)).count == favorites.count else { throw ArchiveError.invalid }
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 20 * 1024 * 1024 else { throw RouteError.tooLarge }
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer(), text = try container.decode(String.self)
            guard let date = fractional.date(from: text) ?? standard.date(from: text) else { throw ArchiveError.invalid }
            return date
        }
        let archive: Self
        do { archive = try decoder.decode(Self.self, from: data) } catch { throw ArchiveError.invalid }
        try archive.validate()
        return archive
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer(); try container.encode(fractional.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 20 * 1024 * 1024 else { throw RouteError.tooLarge }
        return data
    }

    func merging(_ incoming: Self, policy: MergePolicy) throws -> Self {
        try incoming.validate()
        var merged = self
        for item in incoming.favorites {
            if let index = merged.favorites.firstIndex(where: { $0.id == item.id }) {
                if policy == .replaceMatching { merged.favorites[index] = item }
            } else { merged.favorites.append(item) }
        }
        for item in incoming.routes {
            if let index = merged.routes.firstIndex(where: { $0.id == item.id }) {
                if policy == .replaceMatching { merged.routes[index] = item }
            } else { merged.routes.append(item) }
        }
        try merged.validate()
        return merged
    }
}

enum ArchiveError: LocalizedError {
    case invalid, unsupported
    var errorDescription: String? {
        self == .unsupported ? L10n.tr("This backup version or coordinate system is not supported.") : L10n.tr("The backup contains invalid or duplicate data. Your library was not changed.")
    }
}
