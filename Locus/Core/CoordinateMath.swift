import CoreLocation
import Foundation

enum CoordinateMath {
    static func offset(_ origin: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let angularDistance = hypot(eastMeters, northMeters) / 6_371_008.8
        let bearing = atan2(eastMeters, northMeters)
        let latitude = origin.latitude * .pi / 180, longitude = origin.longitude * .pi / 180
        let nextLatitude = asin(sin(latitude) * cos(angularDistance) + cos(latitude) * sin(angularDistance) * cos(bearing))
        let nextLongitude = longitude + atan2(sin(bearing) * sin(angularDistance) * cos(latitude), cos(angularDistance) - sin(latitude) * sin(nextLatitude))
        return .init(latitude: nextLatitude * 180 / .pi, longitude: (nextLongitude * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180)
    }
    static func isValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite && CLLocationCoordinate2DIsValid(coordinate)
    }

    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, fraction: Double) -> CLLocationCoordinate2D {
        let delta = (b.longitude - a.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        let longitude = (a.longitude + delta * fraction + 540).truncatingRemainder(dividingBy: 360) - 180
        return .init(latitude: a.latitude + (b.latitude - a.latitude) * fraction, longitude: longitude)
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func length(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }
}
