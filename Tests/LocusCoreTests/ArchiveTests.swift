import XCTest
@testable import LocusCore

final class ArchiveTests: XCTestCase {
    func testLegacyFavoritesDecodeWithoutGroup() throws {
        let data = Data(#"[{"name":"旧收藏","latitude":31.2,"longitude":121.4}]"#.utf8)
        let items = try JSONDecoder().decode([SavedPlace].self, from: data)
        XCTAssertNil(items[0].group); XCTAssertTrue(items[0].isValid)
    }
    func testMergePoliciesAndHistoryPreservation() throws {
        var local = LibraryArchive(), incoming = LibraryArchive()
        local.favorites = [SavedPlace(name: "old", latitude: 10, longitude: 20)]
        local.recents = local.favorites
        incoming.favorites = [SavedPlace(name: "new", latitude: 10, longitude: 20), SavedPlace(name: "extra", latitude: 20, longitude: 30)]
        XCTAssertEqual(try local.merging(incoming, policy: .keepExisting).favorites.map(\.name), ["old", "extra"])
        let replaced = try local.merging(incoming, policy: .replaceMatching)
        XCTAssertEqual(replaced.favorites.map(\.name), ["new", "extra"])
        XCTAssertEqual(replaced.recents, local.recents)
    }
    func testInvalidDataRejectedBeforeMerge() throws {
        var archive = LibraryArchive()
        archive.favorites = [SavedPlace(name: "invalid", latitude: 91, longitude: 0)]
        XCTAssertThrowsError(try archive.encoded())
        archive.favorites = [SavedPlace(name: "one", latitude: 0, longitude: 0), SavedPlace(name: "two", latitude: 0, longitude: 0)]
        XCTAssertThrowsError(try archive.validate())
        archive = LibraryArchive(); archive.schemaVersion = 2
        XCTAssertThrowsError(try archive.validate())
        XCTAssertThrowsError(try LibraryArchive.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try LibraryArchive.decode(Data(repeating: 0, count: 20 * 1024 * 1024 + 1)))
    }
    func testMetadataRoundTripPreservesMillisecondsAndExcludesPairing() throws {
        var archive = LibraryArchive(), route = SavedRoute()
        route.kind = .gpx; route.name = "河边"
        route.path = [
            RoutePoint(.init(latitude: 31, longitude: 121), name: "起点 & <桥>", timestamp: Date(timeIntervalSince1970: 100.125), elevation: 12.5),
            RoutePoint(.init(latitude: 31.01, longitude: 121.01), timestamp: Date(timeIntervalSince1970: 100.625))
        ]
        route.options.useRecordedTiming = true; archive.routes = [route]
        let data = try archive.encoded(), restored = try LibraryArchive.decode(data)
        XCTAssertEqual(restored.routes[0].path[0].timestamp!.timeIntervalSince1970, 100.125, accuracy: 0.001)
        XCTAssertEqual(try RouteTimeline(route: restored.routes[0]).duration, 0.5, accuracy: 0.001)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("pairing")); XCTAssertFalse(json.contains("PrivateKey"))
        let gpx = GPXCodec.export(points: route.path, name: route.name)
        let segment = try GPXCodec.parse(data: Data(gpx.utf8))[0]
        XCTAssertEqual(segment.name, route.name)
        XCTAssertEqual(segment.points[0].name, route.path[0].name)
        XCTAssertEqual(segment.points[0].elevation, 12.5)
        XCTAssertEqual(segment.points[0].timestamp!.timeIntervalSince1970, 100.125, accuracy: 0.001)
    }
}
