import CoreLocation
import Foundation

enum CoordinateMath {
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
