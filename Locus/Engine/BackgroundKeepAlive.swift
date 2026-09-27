import CoreLocation
import Foundation

/// Idle browsing requests one fix; continuous updates exist only during an
/// explicitly enabled background simulation session.
@MainActor
final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var lastKnownCoordinate: CLLocationCoordinate2D?
    private var activeSession = false
    private var requestedAt: Date?
    private var callbacks: [(String?) -> Void] = []
    private var timeoutTask: Task<Void, Never>?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = true
    }
    func resetLastLocation() { lastKnownCoordinate = nil }
    func requestFreshLocation(completion: @escaping (String?) -> Void) {
        callbacks.append(completion)
        guard requestedAt == nil else { return }
        requestedAt = Date()
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            self?.finish(L10n.tr("No fresh system location was received. Check Location Services and try again."))
        }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(L10n.tr("Location access is disabled. Enable it in iOS Settings to center the map."))
        default: manager.requestLocation()
        }
    }
    func startSession(backgroundEnabled: Bool) {
        guard backgroundEnabled else { stopSession(); return }
        guard !activeSession else { return }
        activeSession = true
        manager.allowsBackgroundLocationUpdates = true
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }
    func stopSession() {
        activeSession = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }
    private func finish(_ error: String?) {
        timeoutTask?.cancel(); timeoutTask = nil; requestedAt = nil
        let pending = callbacks; callbacks.removeAll()
        if !activeSession { manager.stopUpdatingLocation() }
        pending.forEach { $0(error) }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard requestedAt != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .restricted, .denied: finish(L10n.tr("Location access is disabled. Enable it in iOS Settings to center the map."))
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              location.timestamp.timeIntervalSince(requestedAt ?? Date().addingTimeInterval(-15)) >= -1 else { return }
        lastKnownCoordinate = location.coordinate
        if requestedAt != nil { finish(nil) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if requestedAt != nil { finish(error.localizedDescription) }
    }
}
