import CoreLocation
import Foundation

/// A bounded, single-cycle timeline. Repetitions never duplicate the point array.
struct RouteTimeline {
    struct Leg {
        let from: CLLocationCoordinate2D
        let to: CLLocationCoordinate2D
        let start: Double
        let duration: Double
        let startDistance: Double
        let distance: Double
    }
    let legs: [Leg]
    let cycleDuration: Double
    let cycleDistance: Double
    let repetitions: Int
    let first: CLLocationCoordinate2D
    let last: CLLocationCoordinate2D
    var duration: Double { cycleDuration * Double(repetitions) }
    var distance: Double { cycleDistance * Double(repetitions) }

    init(route: SavedRoute) throws {
        guard route.isValid, route.playbackPoints.count >= 2 else { throw RouteError.invalid }
        let original = route.playbackPoints
        if route.options.useRecordedTiming {
            guard original.allSatisfy({ $0.timestamp != nil }), zip(original, original.dropFirst()).allSatisfy({ $0.1.timestamp! > $0.0.timestamp! }) else { throw RouteError.missingTiming }
        }
        var points = route.options.reversed ? Array(original.reversed()) : original
        if route.options.repeatMode == .roundTrip { points += points.dropLast().reversed() }
        if route.options.repeatMode == .loop, let first = points.first, let last = points.last,
           CoordinateMath.distance(first.coordinate, last.coordinate) > 0.01 {
            var closure = first; closure.timestamp = nil; closure.dwellSeconds = 0
            points.append(closure)
        }
        var output: [Leg] = [], time = 0.0, meters = 0.0
        for i in points.indices {
            let point = points[i]
            if i > 0 {
                let previous = points[i - 1]
                let length = CoordinateMath.distance(previous.coordinate, point.coordinate)
                var seconds = length / route.options.metersPerSecond
                if route.options.useRecordedTiming, let a = previous.timestamp, let b = point.timestamp {
                    seconds = abs(b.timeIntervalSince(a))
                }
                if seconds > 0 {
                    output.append(.init(from: previous.coordinate, to: point.coordinate, start: time, duration: seconds, startDistance: meters, distance: length))
                    time += seconds; meters += length
                }
            }
            if point.dwellSeconds > 0 {
                output.append(.init(from: point.coordinate, to: point.coordinate, start: time, duration: point.dwellSeconds, startDistance: meters, distance: 0))
                time += point.dwellSeconds
            }
        }
        guard time.isFinite, time > 0, !output.isEmpty else { throw RouteError.invalid }
        legs = output; cycleDuration = time; cycleDistance = meters
        repetitions = route.options.repeatMode == .once ? 1 : route.options.repetitions
        first = points[0].coordinate; last = points[points.count - 1].coordinate
    }

    func sample(at elapsed: Double) -> (coordinate: CLLocationCoordinate2D, progress: Double, remainingMeters: Double) {
        let value = min(duration, max(0, elapsed))
        if value >= duration { return (last, 1, 0) }
        let cycle = Int(value / cycleDuration)
        let local = value.truncatingRemainder(dividingBy: cycleDuration)
        var low = 0, high = legs.count - 1
        while low < high {
            let mid = (low + high) / 2
            if legs[mid].start + legs[mid].duration <= local { low = mid + 1 } else { high = mid }
        }
        let leg = legs[low], fraction = min(1, max(0, (local - leg.start) / leg.duration))
        let covered = Double(cycle) * cycleDistance + leg.startDistance + fraction * leg.distance
        return (CoordinateMath.interpolate(leg.from, leg.to, fraction: fraction), value / duration, max(0, distance - covered))
    }
}

/// Uptime is monotonic. Includes send latency; pauses and suspension gaps never catch up.
struct MovementClock {
    private var last: Double?
    mutating func reset(at uptime: Double? = nil) { last = uptime }
    mutating func step(at uptime: Double, advancing: Bool) -> (seconds: Double, suspended: Bool) {
        defer { last = uptime }
        guard let previous = last, advancing else { return (0, false) }
        let delta = uptime - previous
        guard delta >= 0, delta <= 2 else { return (0, true) }
        return (delta, false)
    }
}
