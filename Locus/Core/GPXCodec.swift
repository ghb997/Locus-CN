import CoreLocation
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct GPXSegment: Identifiable {
    let id: Int
    var name: String = ""
    var points: [RoutePoint]
    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
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
    static let maximumBytes = 10 * 1024 * 1024
    static let maximumPoints = 100_000
    static func parse(_ url: URL) throws -> [GPXSegment] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes { throw GPXError.tooLarge }
        return try parse(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
    static func parse(data: Data) throws -> [GPXSegment] {
        guard data.count <= maximumBytes else { throw GPXError.tooLarge }
        let reader = GPXReader(), parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = reader
        let success = parser.parse()
        if let error = reader.error { throw error }
        guard success, reader.isGPX else { throw GPXError.invalidXML }
        let result = reader.segments.isEmpty && !reader.waypoints.isEmpty ? [GPXSegment(id: 0, points: reader.waypoints)] : reader.segments
        guard !result.isEmpty else { throw GPXError.noPoints }
        return result
    }
    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = "Locus Route") -> String {
        export(points: coordinates.map { RoutePoint($0) }, name: name)
    }
    static func export(points: [RoutePoint], name: String) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body = points.filter(\.isValid).map { point -> String in
            var value = String(format: "<trkpt lat=\"%.8f\" lon=\"%.8f\">", locale: Locale(identifier: "en_US_POSIX"), point.latitude, point.longitude)
            if let elevation = point.elevation { value += "<ele>\(elevation)</ele>" }
            if let date = point.timestamp { value += "<time>\(formatter.string(from: date))</time>" }
            if !point.name.isEmpty { value += "<name>\(escape(point.name))</name>" }
            return value + "</trkpt>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Locus CN" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(escape(name))</name><trkseg>
        \(body)
        </trkseg></trk></gpx>
        """
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
}

private final class GPXReader: NSObject, XMLParserDelegate {
    var segments: [GPXSegment] = [], waypoints: [RoutePoint] = []
    var error: GPXError?
    var isGPX = false
    private var path: [String] = [], current: [RoutePoint] = []
    private var pending: RoutePoint?, pointDepth = 0, count = 0
    private var text = "", trackName = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if path.isEmpty { isGPX = name == "gpx" }
        path.append(name); text = ""
        guard isGPX, path.count < 128 else { fail(.invalidXML, parser); return }
        if path == ["gpx", "trk"] || path == ["gpx", "rte"] { trackName = "" }
        if path == ["gpx", "trk", "trkseg"] || path == ["gpx", "rte"] { current = [] }
        let track = path == ["gpx", "trk", "trkseg", "trkpt"] || path == ["gpx", "rte", "rtept"]
        guard track || path == ["gpx", "wpt"] else { return }
        guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) else { fail(.invalidCoordinate, parser); return }
        let point = RoutePoint(.init(latitude: lat, longitude: lon))
        guard point.isValid else { fail(.invalidCoordinate, parser); return }
        count += 1
        guard count <= GPXCodec.maximumPoints else { fail(.tooManyPoints, parser); return }
        pending = point; pointDepth = path.count
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if text.count < 2048 { text += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if path == ["gpx", "trk", "name"] || path == ["gpx", "rte", "name"] { trackName = String(value.prefix(200)) }
        if pending != nil, path.count == pointDepth + 1 {
            if name == "name" { pending?.name = String(value.prefix(200)) }
            if name == "ele" {
                guard let height = Double(value), height.isFinite else { fail(.invalidXML, parser); return }
                pending?.elevation = height
            }
            if name == "time" {
                let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { fail(.invalidXML, parser); return }
                pending?.timestamp = date
            }
        }
        if let point = pending, path.count == pointDepth {
            if path == ["gpx", "wpt"] { waypoints.append(point) } else { current.append(point) }
            pending = nil
        }
        if path == ["gpx", "trk", "trkseg"] || path == ["gpx", "rte"] {
            if !current.isEmpty { segments.append(.init(id: segments.count, name: trackName, points: current)) }
            current = []
        }
        if !path.isEmpty { path.removeLast() }
        text = ""
    }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { fail(.invalidXML, parser) }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { fail(.invalidXML, parser) }
    private func fail(_ reason: GPXError, _ parser: XMLParser) { error = reason; parser.abortParsing() }
}
