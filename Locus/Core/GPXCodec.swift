import CoreLocation
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct GPXSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
}

enum GPXError: LocalizedError {
    case tooLarge, invalidXML, invalidCoordinate, noPoints, tooManyPoints

    var errorDescription: String? {
        switch self {
        case .tooLarge: return L10n.tr("GPX files must be smaller than 10 MB.")
        case .invalidXML: return L10n.tr("This file is not a valid GPX document.")
        case .invalidCoordinate: return L10n.tr("The GPX contains invalid coordinates. Latitude must be −90…90 and longitude −180…180.")
        case .noPoints: return L10n.tr("No track points found in GPX")
        case .tooManyPoints: return L10n.tr("The GPX exceeds the 100,000 point limit.")
        }
    }
}

enum GPXCodec {
    static let maximumBytes = 10 * 1_024 * 1_024
    static let maximumPoints = 100_000

    static func parse(_ url: URL) throws -> [GPXSegment] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes {
            throw GPXError.tooLarge
        }
        return try parse(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func parse(data: Data) throws -> [GPXSegment] {
        guard data.count <= maximumBytes else { throw GPXError.tooLarge }
        let reader = GPXReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        let success = parser.parse()
        if let error = reader.error { throw error }
        guard success, reader.isGPX else { throw GPXError.invalidXML }
        let segments = reader.segments.isEmpty ? [reader.waypoints] : reader.segments
        let nonempty = segments.filter { !$0.isEmpty }
        guard !nonempty.isEmpty else { throw GPXError.noPoints }
        return nonempty.enumerated().map { GPXSegment(id: $0.offset, coordinates: $0.element) }
    }

    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = "Locus Route") -> String {
        let safeName = name.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
        let points = coordinates.filter(CoordinateMath.isValid).map {
            String(format: "<trkpt lat=\"%.8f\" lon=\"%.8f\"/>", locale: Locale(identifier: "en_US_POSIX"), $0.latitude, $0.longitude)
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Locus CN" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(safeName)</name><trkseg>
        \(points)
        </trkseg></trk></gpx>
        """
    }
}

private final class GPXReader: NSObject, XMLParserDelegate {
    var segments: [[CLLocationCoordinate2D]] = []
    var waypoints: [CLLocationCoordinate2D] = []
    var error: GPXError?
    var isGPX = false
    private var path: [String] = []
    private var current: [CLLocationCoordinate2D] = []
    private var count = 0

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if path.isEmpty { isGPX = name == "gpx" }
        path.append(name)
        guard isGPX, path.count < 128 else { fail(.invalidXML, parser); return }
        if path == ["gpx", "trk", "trkseg"] || path == ["gpx", "rte"] { current = [] }
        let isTrack = path == ["gpx", "trk", "trkseg", "trkpt"] || path == ["gpx", "rte", "rtept"]
        let isWaypoint = path == ["gpx", "wpt"]
        guard isTrack || isWaypoint else { return }
        guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) else {
            fail(.invalidCoordinate, parser); return
        }
        let point = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        guard CoordinateMath.isValid(point) else { fail(.invalidCoordinate, parser); return }
        count += 1
        guard count <= GPXCodec.maximumPoints else { fail(.tooManyPoints, parser); return }
        if isWaypoint { waypoints.append(point) } else { current.append(point) }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if path == ["gpx", "trk", "trkseg"] || path == ["gpx", "rte"] {
            if !current.isEmpty { segments.append(current) }
            current = []
        }
        if !path.isEmpty { path.removeLast() }
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { fail(.invalidXML, parser) }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { fail(.invalidXML, parser) }

    private func fail(_ reason: GPXError, _ parser: XMLParser) {
        error = reason
        parser.abortParsing()
    }
}
