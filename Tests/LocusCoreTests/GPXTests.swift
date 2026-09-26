import CoreLocation
import XCTest
@testable import LocusCore

final class GPXTests: XCTestCase {
    private func parse(_ xml: String) throws -> [GPXSegment] { try GPXCodec.parse(data: Data(xml.utf8)) }

    func testMixedAttributeOrderQuotesAndNamespaces() throws {
        let segments = try parse("""
        <gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
        <trkpt lat='31.2' lon='121.4'/><trkpt lon="121.5" lat="31.3"/>
        </trkseg></trk></gpx>
        """)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].coordinates.count, 2)
        XCTAssertEqual(segments[0].coordinates[1].latitude, 31.3)
    }

    func testSegmentsNeverJoinedAndMetadataCoordinatesIgnored() throws {
        let segments = try parse("""
        <gpx><metadata lat="0" lon="0"/><trk>
        <trkseg><trkpt lat="31" lon="121"/></trkseg>
        <trkseg><trkpt lat="40" lon="116"/></trkseg>
        </trk></gpx>
        """)
        XCTAssertEqual(segments.map { $0.coordinates.count }, [1, 1])
        XCTAssertEqual(segments[1].coordinates[0].latitude, 40)
    }

    func testRouteAndWaypointFallback() throws {
        XCTAssertEqual(try parse("<gpx><rte><rtept lon='20' lat='10'/></rte></gpx>")[0].coordinates.count, 1)
        XCTAssertEqual(try parse("<gpx><wpt lat='10' lon='20'/></gpx>")[0].coordinates[0].longitude, 20)
    }

    func testRejectsMalformedXMLWrongRootAndInvalidCoordinates() {
        for xml in ["<gpx><trk>", "<html/>", "<gpx/>",
                    "<gpx><wpt lat='91' lon='0'/></gpx>",
                    "<gpx><wpt lat='nan' lon='0'/></gpx>",
                    "<gpx><wpt lat='0' lon='181'/></gpx>",
                    "<gpx><wpt lat='0'/></gpx>"] {
            XCTAssertThrowsError(try parse(xml), xml)
        }
    }

    func testRejectsOversizeDataAndEntityDeclarations() {
        XCTAssertThrowsError(try GPXCodec.parse(data: Data(repeating: 32, count: GPXCodec.maximumBytes + 1)))
        XCTAssertThrowsError(try parse("<!DOCTYPE gpx [<!ENTITY x '1'>]><gpx><wpt lat='&x;' lon='2'/></gpx>"))
    }

    func testRoundTripEscapesNamesAndPreservesCoordinates() throws {
        let points = [CLLocationCoordinate2D(latitude: -33.8568, longitude: 151.2153),
                      CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)]
        let exported = GPXCodec.export(points, name: "A & B <测试> \"'")
        XCTAssertTrue(exported.contains("A &amp; B &lt;测试&gt; &quot;&apos;"))
        let result = try parse(exported)[0].coordinates
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].longitude, points[0].longitude, accuracy: 0.00000001)
        XCTAssertEqual(result[1].latitude, points[1].latitude, accuracy: 0.00000001)
    }

    func testInternationalDateLineInterpolationTakesShortPath() {
        let middle = CoordinateMath.interpolate(.init(latitude: 0, longitude: 179), .init(latitude: 0, longitude: -179), fraction: 0.5)
        XCTAssertEqual(abs(middle.longitude), 180, accuracy: 0.0001)
        XCTAssertFalse(CoordinateMath.isValid(.init(latitude: .infinity, longitude: 0)))
    }
}
