import CoreLocation
import Foundation
import MapKit

enum RouteBuilder {
    static func roadRoute(waypoints: [RoutePoint], mode: TravelMode, closed: Bool) async throws -> [RoutePoint] {
        guard (2...200).contains(waypoints.count), waypoints.allSatisfy(\.isValid) else { throw RouteError.invalid }
        var stops = waypoints
        if closed { var closing = waypoints[0]; closing.dwellSeconds = 0; stops.append(closing) }
        var output: [RoutePoint] = []
        for (start, end) in zip(stops, stops.dropFirst()) {
            try Task.checkCancellation()
            let coordinates = try await roadRoute(from: start.coordinate, to: end.coordinate, mode: mode)
            guard coordinates.count >= 2 else { throw RouteError.invalid }
            var points = coordinates.map { RoutePoint($0) }
            // Include the exact selected endpoints; MapKit may snap road geometry.
            points.insert(start, at: 0); points.append(end)
            if !output.isEmpty { points.removeFirst() }
            output += points
            guard output.count <= 100_000 else { throw RouteError.tooLarge }
        }
        return output
    }
    static func roadRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        mode: TravelMode
    ) async throws -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = mode.mkTransportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await withTaskCancellationHandler(operation: { try await directions.calculate() }, onCancel: { directions.cancel() })
        try Task.checkCancellation()
        guard let route = response.routes.first else {
            throw NSError(domain: "Locus", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("No route found")])
        }
        var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: route.polyline.pointCount)
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
        return coordinates
    }

}
