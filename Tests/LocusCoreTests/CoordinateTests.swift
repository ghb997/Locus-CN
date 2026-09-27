import CoreLocation
import XCTest
@testable import LocusCore

final class CoordinateTests: XCTestCase {
    func testExplicitCoordinateOrderAndValidation() throws {
        let point = try CoordinateConverter.parse("116.404，39.915", longitudeFirst: true)
        XCTAssertEqual(point.latitude, 39.915)
        XCTAssertEqual(point.longitude, 116.404)
        for text in ["91,0", "0,181", "nan 10", "0 infinity", "1 2 3", "1", ""] {
            XCTAssertThrowsError(try CoordinateConverter.parse(text))
        }
        XCTAssertEqual(try CoordinateConverter.parse("-90; -180").latitude, -90)
    }
    func testBeijingReferenceAndInverse() {
        // Conventional GCJ formula reference at WGS-84 39.915, 116.404.
        let wgs = CLLocationCoordinate2D(latitude: 39.915, longitude: 116.404)
        let gcj = CoordinateConverter.convert(wgs, from: .wgs84, to: .gcj02)
        XCTAssertEqual(gcj.latitude, 39.9164042815, accuracy: 0.0000001)
        XCTAssertEqual(gcj.longitude, 116.4102444992, accuracy: 0.0000001)
        let restored = CoordinateConverter.convert(gcj, from: .gcj02)
        XCTAssertLessThan(CoordinateMath.distance(wgs, restored), 0.1)
        let bd = CoordinateConverter.convert(wgs, from: .wgs84, to: .bd09)
        XCTAssertEqual(bd.latitude, 39.9226995522, accuracy: 0.000002)
        XCTAssertEqual(bd.longitude, 116.4166272438, accuracy: 0.000002)
        XCTAssertLessThan(CoordinateMath.distance(wgs, CoordinateConverter.convert(bd, from: .bd09)), 1)
    }
    func testOverseasIdentityAndExplicitIdentity() {
        for point in [CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12), .init(latitude: -33.8, longitude: 151.2)] {
            let result = CoordinateConverter.convert(point, from: .wgs84, to: .gcj02)
            XCTAssertEqual(result.latitude, point.latitude); XCTAssertEqual(result.longitude, point.longitude)
        }
        let point = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        XCTAssertEqual(CoordinateConverter.convert(point, from: .wgs84).longitude, point.longitude)
    }
    func testGeodesicJoystickCrossesDatelineAndStaysValidAtPole() {
        let moved = CoordinateMath.offset(.init(latitude: 0, longitude: 179.999), eastMeters: 500, northMeters: 0)
        XCTAssertTrue(CoordinateMath.isValid(moved)); XCTAssertLessThan(moved.longitude, -179.99)
        XCTAssertEqual(CoordinateMath.distance(.init(latitude: 0, longitude: 179.999), moved), 500, accuracy: 4)
        XCTAssertTrue(CoordinateMath.isValid(CoordinateMath.offset(.init(latitude: 90, longitude: 0), eastMeters: 5, northMeters: 0)))
    }
}
