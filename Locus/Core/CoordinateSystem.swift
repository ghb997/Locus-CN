import CoreLocation
import Foundation

enum CoordinateSystem: String, Codable, CaseIterable, Identifiable {
    case wgs84 = "WGS-84", gcj02 = "GCJ-02", bd09 = "BD-09"
    var id: String { rawValue }
}

enum CoordinateInputError: LocalizedError {
    case invalid
    var errorDescription: String? { L10n.tr("Enter two decimal coordinates: latitude, longitude. Check their order and range.") }
}

/// Core Location and MapKit's CLLocationCoordinate2D contract is WGS 84.
/// Conversion is ONLY applied to explicitly labelled external input/output.
enum CoordinateConverter {
    static func parse(_ text: String, longitudeFirst: Bool = false) throws -> CLLocationCoordinate2D {
        let parts = text.replacingOccurrences(of: "，", with: ",")
            .split { $0 == "," || $0 == ";" || $0.isWhitespace }
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) else { throw CoordinateInputError.invalid }
        let result = CLLocationCoordinate2D(latitude: longitudeFirst ? b : a, longitude: longitudeFirst ? a : b)
        guard CoordinateMath.isValid(result) else { throw CoordinateInputError.invalid }
        return result
    }

    static func convert(_ coordinate: CLLocationCoordinate2D, from source: CoordinateSystem, to target: CoordinateSystem = .wgs84) -> CLLocationCoordinate2D {
        guard source != target else { return coordinate }
        var wgs = coordinate
        if source == .bd09 { wgs = bdToGCJ(wgs) }
        if source != .wgs84 { wgs = gcjToWGS(wgs) }
        if target == .wgs84 { return wgs }
        let gcj = wgsToGCJ(wgs)
        return target == .gcj02 ? gcj : gcjToBD(gcj)
    }

    static func label(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), c.latitude, c.longitude)
    }

    // GCJ's conventional applicability envelope; explicit selection is required.
    // Border regions still require fixture/device verification; do not infer CRS from a location.
    private static func outside(_ c: CLLocationCoordinate2D) -> Bool {
        c.longitude < 72.004 || c.longitude > 137.8347 || c.latitude < 0.8293 || c.latitude > 55.8271
    }

    private static func wgsToGCJ(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !outside(c) else { return c }
        let x = c.longitude - 105, y = c.latitude - 35
        var lat = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        var lon = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        let wave = (20*sin(6*x * .pi) + 20*sin(2*x * .pi))*2/3
        lat += wave + (20*sin(y * .pi) + 40*sin(y / 3 * .pi))*2/3
        lat += (160*sin(y / 12 * .pi) + 320*sin(y * .pi / 30))*2/3
        lon += wave + (20*sin(x * .pi) + 40*sin(x / 3 * .pi))*2/3
        lon += (150*sin(x / 12 * .pi) + 300*sin(x / 30 * .pi))*2/3
        let rad = c.latitude * .pi / 180
        let magic = 1 - 0.00669342162296594323 * pow(sin(rad), 2)
        lat = lat * 180 / ((6_378_245 * (1 - 0.00669342162296594323)) / pow(magic, 1.5) * .pi)
        lon = lon * 180 / (6_378_245 / sqrt(magic) * cos(rad) * .pi)
        return .init(latitude: c.latitude + lat, longitude: c.longitude + lon)
    }

    private static func gcjToWGS(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !outside(c) else { return c }
        var guess = c
        for _ in 0..<10 {
            let forward = wgsToGCJ(guess)
            let dLat = forward.latitude - c.latitude, dLon = forward.longitude - c.longitude
            guess.latitude -= dLat; guess.longitude -= dLon
            if max(abs(dLat), abs(dLon)) < 1e-9 { break }
        }
        return guess
    }

    private static func gcjToBD(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let k = Double.pi * 3000 / 180
        let z = hypot(c.longitude, c.latitude) + 0.00002 * sin(c.latitude * k)
        let theta = atan2(c.latitude, c.longitude) + 0.000003 * cos(c.longitude * k)
        return .init(latitude: z*sin(theta) + 0.006, longitude: z*cos(theta) + 0.0065)
    }

    private static func bdToGCJ(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = c.longitude - 0.0065, y = c.latitude - 0.006, k = Double.pi * 3000 / 180
        let z = hypot(x, y) - 0.00002 * sin(y*k)
        let theta = atan2(y, x) - 0.000003 * cos(x*k)
        return .init(latitude: z*sin(theta), longitude: z*cos(theta))
    }
}
