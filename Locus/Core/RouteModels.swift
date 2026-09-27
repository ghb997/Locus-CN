import CoreLocation
import Foundation

struct RoutePoint: Codable, Equatable, Identifiable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    var name = ""
    var dwellSeconds = 0.0
    var timestamp: Date?
    var elevation: Double?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    init(_ coordinate: CLLocationCoordinate2D, name: String = "", dwellSeconds: Double = 0, timestamp: Date? = nil, elevation: Double? = nil) {
        latitude = coordinate.latitude; longitude = coordinate.longitude
        self.name = name; self.dwellSeconds = dwellSeconds; self.timestamp = timestamp; self.elevation = elevation
    }

    var isValid: Bool {
        CoordinateMath.isValid(coordinate) && name.count <= 200 && dwellSeconds.isFinite && (0...3600).contains(dwellSeconds)
            && (elevation == nil || elevation!.isFinite) && (timestamp == nil || timestamp!.timeIntervalSince1970.isFinite)
    }
}

enum RouteKind: String, Codable, CaseIterable, Identifiable {
    case straight, road, gpx
    var id: String { rawValue }
    var title: String {
        switch self { case .straight: return L10n.tr("Straight lines"); case .road: return L10n.tr("Road route"); case .gpx: return L10n.tr("GPX track") }
    }
}

enum RouteRepeatMode: String, Codable, CaseIterable, Identifiable {
    case once, roundTrip, loop
    var id: String { rawValue }
    var title: String {
        switch self { case .once: return L10n.tr("One way"); case .roundTrip: return L10n.tr("Round trip"); case .loop: return L10n.tr("Closed loop") }
    }
}

struct PlaybackOptions: Codable, Equatable {
    var metersPerSecond = 1.4
    var repeatMode: RouteRepeatMode = .once
    var repetitions = 1
    var reversed = false
    var useRecordedTiming = false
    var isValid: Bool { metersPerSecond.isFinite && (0.1...60).contains(metersPerSecond) && (1...100).contains(repetitions) }
}

struct SavedRoute: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var kind: RouteKind = .straight
    /// All stored points are WGS-84, including converted imports.
    var waypoints: [RoutePoint] = []
    var path: [RoutePoint] = []
    var options = PlaybackOptions()
    var updatedAt = Date()
    var playbackPoints: [RoutePoint] { kind == .road || kind == .gpx ? path : waypoints }
    var isValid: Bool {
        name.count <= 200 && options.isValid && waypoints.count <= 100_000 && path.count <= 100_000
            && waypoints.allSatisfy(\.isValid) && path.allSatisfy(\.isValid)
    }
}

enum RouteError: LocalizedError {
    case invalid, missingTiming, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalid: return L10n.tr("The route needs at least two valid points and a valid speed.")
        case .missingTiming: return L10n.tr("Recorded playback requires an increasing timestamp on every GPX point.")
        case .tooLarge: return L10n.tr("The route or backup exceeds the supported size limit.")
        }
    }
}

struct SessionCheckpoint: Codable {
    var coordinate: RoutePoint
    var route: SavedRoute?
    var elapsed: Double
    var date = Date()
    var isValid: Bool { coordinate.isValid && elapsed.isFinite && elapsed >= 0 && (route?.isValid ?? true) }
}
