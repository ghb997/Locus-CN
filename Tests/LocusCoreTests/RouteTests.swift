import CoreLocation
import XCTest
@testable import LocusCore

final class RouteTests: XCTestCase {
    private func route() -> SavedRoute {
        var route = SavedRoute()
        route.waypoints = [RoutePoint(.init(latitude: 0, longitude: 0)), RoutePoint(.init(latitude: 0, longitude: 0.001))]
        route.options.metersPerSecond = 2
        return route
    }
    func testDwellProgressAndFinalPosition() throws {
        var route = route(); route.waypoints[0].dwellSeconds = 5; route.waypoints[1].dwellSeconds = 3
        let timeline = try RouteTimeline(route: route)
        XCTAssertEqual(timeline.duration, timeline.distance / 2 + 8, accuracy: 0.001)
        XCTAssertEqual(timeline.sample(at: 4).coordinate.longitude, 0)
        XCTAssertGreaterThan(timeline.sample(at: 8).coordinate.longitude, 0)
        XCTAssertEqual(timeline.sample(at: timeline.duration + 10).coordinate.longitude, 0.001)
        XCTAssertEqual(timeline.sample(at: timeline.duration).progress, 1)
    }
    func testRoundTripLoopReverseAndBoundedRepetitions() throws {
        var route = route(); route.options.repeatMode = .roundTrip; route.options.repetitions = 100
        let timeline = try RouteTimeline(route: route)
        XCTAssertEqual(timeline.legs.count, 2)
        XCTAssertEqual(timeline.duration, timeline.cycleDuration * 100)
        XCTAssertEqual(timeline.sample(at: timeline.duration).coordinate.longitude, 0)
        route.options.repeatMode = .loop
        XCTAssertEqual(try RouteTimeline(route: route).last.longitude, 0)
        route.options.repeatMode = .once; route.options.reversed = true
        let reversed = try RouteTimeline(route: route)
        XCTAssertEqual(reversed.first.longitude, 0.001); XCTAssertEqual(reversed.last.longitude, 0)
    }
    func testRecordedTimeAndReverseRequireStrictlyIncreasingDates() throws {
        var route = route(); route.options.useRecordedTiming = true
        XCTAssertThrowsError(try RouteTimeline(route: route))
        route.waypoints[0].timestamp = Date(timeIntervalSince1970: 100.125)
        route.waypoints[1].timestamp = Date(timeIntervalSince1970: 101.625)
        XCTAssertEqual(try RouteTimeline(route: route).duration, 1.5)
        route.options.reversed = true
        XCTAssertEqual(try RouteTimeline(route: route).duration, 1.5)
        route.waypoints[1].timestamp = route.waypoints[0].timestamp
        XCTAssertThrowsError(try RouteTimeline(route: route))
    }
    func testClockIncludesSendLatencyAndDiscardsPauseSuspension() {
        for latency in [0.0, 0.1, 0.5] {
            var clock = MovementClock(), now = 0.0, elapsed = 0.0
            clock.reset(at: now)
            for _ in 0..<20 {
                now += 0.2 + latency
                elapsed += clock.step(at: now, advancing: true).seconds
            }
            XCTAssertEqual(elapsed, now, accuracy: 0.000001)
        }
        var clock = MovementClock(); clock.reset(at: 0)
        XCTAssertEqual(clock.step(at: 1, advancing: true).seconds, 1)
        XCTAssertEqual(clock.step(at: 50, advancing: false).seconds, 0)
        clock.reset(at: 50)
        XCTAssertEqual(clock.step(at: 50.2, advancing: true).seconds, 0.2, accuracy: 0.00001)
        XCTAssertTrue(clock.step(at: 60, advancing: true).suspended)
        XCTAssertEqual(clock.step(at: 60.2, advancing: true).seconds, 0.2, accuracy: 0.00001)
    }
    func testInvalidRoutesAndDateline() throws {
        var route = route(); route.options.metersPerSecond = 0
        XCTAssertThrowsError(try RouteTimeline(route: route))
        route.options.metersPerSecond = 2
        route.waypoints[0].longitude = 179; route.waypoints[1].longitude = -179
        let timeline = try RouteTimeline(route: route)
        XCTAssertEqual(abs(timeline.sample(at: timeline.duration / 2).coordinate.longitude), 180, accuracy: 0.0001)
        XCTAssertEqual(timeline.sample(at: -10).progress, 0)
    }
}
