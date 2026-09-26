import CoreLocation
import Foundation
import MapKit
import UIKit
import UserNotifications

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return L10n.tr("Walk")
        case .run: return L10n.tr("Run")
        case .cycle: return L10n.tr("Cycle")
        case .drive: return L10n.tr("Drive")
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        }
    }

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4
        case .run: return 3.3
        case .cycle: return 6.5
        case .drive: return 13.4
        }
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .run: return .walking
        case .cycle, .drive: return .automobile
        }
    }
}

enum SpoofStatus: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case stopping
    case dropped(String)

    var label: String {
        switch self {
        case .idle: return L10n.tr("Not Spoofing")
        case .connecting: return L10n.tr("Starting…")
        case .active: return L10n.tr("Spoofing")
        case .reconnecting: return L10n.tr("Reconnecting…")
        case .stopping: return L10n.tr("Stopping…")
        case .dropped: return L10n.tr("Interrupted")
        }
    }

    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    @Published var mapStyleIndex = 0
    @Published var lastError: String?
    @Published private(set) var isBusy = false
    @Published private(set) var joystickActive = false
    @Published private(set) var routeActive = false
    @Published private(set) var routePaused = false
    @Published private(set) var routeProgress = 0.0
    @Published private(set) var routeRemainingMeters = 0.0
    @Published private(set) var lastCommandAt: Date?
    @Published var speedMultiplier = 1.0
    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []

    private var resendTimer: Timer?
    private var joystickTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var generation = LocationEngine.beginSession()
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()
    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
    }

    var isSpoofing: Bool { status == .active || status == .reconnecting }
    var canStop: Bool { status != .idle }
    var isStopping: Bool { status == .stopping }
    /// CLLocationManager can report a simulated or cached fix; never call it real GPS.
    var systemCoordinate: CLLocationCoordinate2D? { locationKeeper.lastKnownCoordinate }
    var routeRemainingSeconds: Double { routeRemainingMeters / max(0.1, travelMode.baseSpeed * speedMultiplier) }

    func startLocationUpdates() { locationKeeper.start() }

    private func ready(_ pairing: PairingStore) -> Bool {
        guard !isStopping else { return false }
        guard pairing.hasPairingFile else {
            lastError = L10n.tr("Import an RPPairing file in Settings first.")
            return false
        }
        return true
    }

    /// All movement sources share one epoch. Changing mode also invalidates queued
    /// native writes and late UI completions from the previous movement source.
    @discardableResult
    private func beginMovement() -> UUID {
        generation = LocationEngine.beginSession()
        routeTask?.cancel()
        actionTask?.cancel()
        routeTask = nil
        actionTask = nil
        routeActive = false
        routePaused = false
        routeProgress = 0
        routeRemainingMeters = 0
        joystickActive = false
        joystickVector = .zero
        joystickTimer?.invalidate()
        joystickTimer = nil
        resendTimer?.invalidate()
        resendTimer = nil
        isBusy = false
        return generation
    }

    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard ready(pairing) else { return }
        guard CoordinateMath.isValid(coordinate) else {
            lastError = LocationEngineError.invalidCoordinate.localizedDescription
            return
        }
        let epoch = beginMovement()
        pin = coordinate
        actionTask = Task { [weak self] in
            _ = await self?.apply(coordinate, pairing: pairing, epoch: epoch, markRecent: true)
        }
    }

    func stop(pairing: PairingStore) {
        guard !isStopping else { return }
        let epoch = beginMovement()
        status = .stopping
        isBusy = true
        // Enqueue the clear NOW, before yielding the main actor.
        LocationEngine.clear(pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP) { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == epoch else { return }
                self.isBusy = false
                self.endBackground()
                switch result {
                case .success:
                    self.simulated = nil
                    self.status = .idle
                    self.lastError = nil
                    self.lastCommandAt = nil
                    self.locationKeeper.resetLastLocation()
                    self.locationKeeper.start()
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.status = .dropped(error.localizedDescription)
                    self.postDropNotification(error.localizedDescription)
                }
            }
        }
    }

    func startJoystick(pairing: PairingStore) {
        guard ready(pairing) else { return }
        guard let start = simulated ?? pin ?? systemCoordinate else {
            lastError = L10n.tr("Drop a pin or teleport somewhere before using the joystick.")
            return
        }
        let epoch = beginMovement()
        joystickActive = true
        actionTask = Task { [weak self] in
            guard let self, await self.apply(start, pairing: pairing, epoch: epoch, markRecent: false),
                  self.generation == epoch, self.joystickActive else { return }
            self.joystickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == epoch, !self.isBusy else { return }
                    await self.tickJoystick(pairing: pairing, epoch: epoch)
                }
            }
        }
    }

    func updateJoystick(vector: CGVector) { joystickVector = vector }

    func stopJoystick() {
        joystickActive = false
        joystickVector = .zero
        joystickTimer?.invalidate()
        joystickTimer = nil
        // Any in-flight native write finishes before subsequent commands. Do not
        // allow a new tick, and retain its truthful completion/held coordinate.
    }

    func toggleRoutePause() {
        guard routeActive else { return }
        routePaused.toggle()
    }

    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {
        guard ready(pairing) else { return }
        guard coordinates.count >= 2, coordinates.allSatisfy(CoordinateMath.isValid) else {
            lastError = L10n.tr("Build or draw a route first.")
            return
        }
        let epoch = beginMovement()
        routeActive = true
        let totalDistance = CoordinateMath.length(coordinates)
        routeRemainingMeters = totalDistance
        routeTask = Task { [weak self] in
            guard let self else { return }
            guard await self.apply(coordinates[0], pairing: pairing, epoch: epoch, markRecent: true) else { return }
            var travelled = 0.0
            for (previous, next) in zip(coordinates, coordinates.dropFirst()) {
                let distance = CoordinateMath.distance(previous, next)
                // Bound memory: interpolate one point at a time, never allocate a
                // 10-metre sample array for an entire intercontinental track.
                let steps = max(1, Int(ceil(distance / 5)))
                for index in 1...steps {
                    guard await self.waitUntilRunning(epoch) else { return }
                    let speed = max(0.1, self.travelMode.baseSpeed * min(4, max(0.25, self.speedMultiplier)))
                    let delay = distance / Double(steps) / speed
                    do { try await Task.sleep(nanoseconds: UInt64(min(60, delay) * 1_000_000_000)) }
                    catch { return }
                    guard await self.waitUntilRunning(epoch) else { return }
                    let point = CoordinateMath.interpolate(previous, next, fraction: Double(index) / Double(steps))
                    guard await self.apply(point, pairing: pairing, epoch: epoch, markRecent: false) else { return }
                    travelled += distance / Double(steps)
                    self.routeRemainingMeters = max(0, totalDistance - travelled)
                    self.routeProgress = totalDistance > 0 ? min(1, travelled / totalDistance) : 1
                }
            }
            guard self.generation == epoch, !Task.isCancelled else { return }
            self.routeActive = false
            self.routePaused = false
            self.routeProgress = 1
            self.routeRemainingMeters = 0
            self.routeTask = nil
            // Hold the destination until the user explicitly presses Stop.
        }
    }

    private func waitUntilRunning(_ epoch: UUID) async -> Bool {
        while routePaused {
            guard generation == epoch, !Task.isCancelled else { return false }
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return false }
        }
        return generation == epoch && !Task.isCancelled && routeActive
    }

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorites.first(where: { $0.id == place.id }),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        favorites.removeAll { $0.id == place.id }
        favorites.insert(place, at: 0)
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func renameFavorite(_ place: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index].name = trimmed
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeFavorite(_ place: SavedPlace) {
        favorites.removeAll { $0.id == place.id }
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }

    /// Best display name for starring the current pin (search title, matching recent, etc.).
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favorite = favorites.first(where: { $0.id == SavedPlace(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude).id }),
           !Self.isGenericFavoriteName(favorite.name) {
            return favorite.name
        }
        if let recent = recents.first(where: {
            abs($0.latitude - coordinate.latitude) < 0.00015 && abs($0.longitude - coordinate.longitude) < 0.00015
        }), !Self.isGenericFavoriteName(recent.name) {
            return recent.name
        }
        return Self.coordinateLabel(coordinate)
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func isGenericFavoriteName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Favorite" { return true }
        // Coordinate-looking labels from older teleports.
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
           Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, epoch: UUID, markRecent: Bool) async -> Bool {
        guard generation == epoch, !Task.isCancelled, !isStopping else { return false }
        if status == .idle { status = .connecting }
        isBusy = true
        let result: Result<Void, LocationEngineError> = await withCheckedContinuation { continuation in
            LocationEngine.set(latitude: coordinate.latitude, longitude: coordinate.longitude,
                               pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP, generation: epoch) {
                continuation.resume(returning: $0)
            }
        }
        // An old completion must never change the state of a newer session.
        guard generation == epoch else { return false }
        isBusy = false
        switch result {
        case .success:
            simulated = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            lastCommandAt = Date()
            beginBackground()
            locationKeeper.start()
            startResend(pairing: pairing, epoch: epoch)
            if markRecent { pushRecent(coordinate) }
            return true
        case .failure(.cancelled):
            return false
        case .failure(let error):
            let wasDropped = status.isDropped
            lastError = error.localizedDescription
            status = .dropped(error.localizedDescription)
            routeActive = false
            routePaused = false
            stopJoystick()
            resendTimer?.invalidate()
            resendTimer = nil
            endBackground()
            if !wasDropped { postDropNotification(error.localizedDescription) }
            return false
        }
    }

    private func tickJoystick(pairing: PairingStore, epoch: UUID) async {
        guard joystickActive, let current = simulated else { return }
        let magnitude = hypot(joystickVector.dx, joystickVector.dy)
        guard magnitude > 0.08 else { return }
        let speed = travelMode.baseSpeed * min(4, max(0.25, speedMultiplier)) * min(1, magnitude)
        let meters = speed * 0.25
        let next = offset(coordinate: current, eastMeters: joystickVector.dx / magnitude * meters,
                          northMeters: -joystickVector.dy / magnitude * meters)
        _ = await apply(next, pairing: pairing, epoch: epoch, markRecent: false)
    }

    private func startResend(pairing: PairingStore, epoch: UUID) {
        guard resendTimer == nil else { return }
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == epoch, !self.isBusy,
                      !self.isStopping, !self.status.isDropped, let coordinate = self.simulated else { return }
                if self.routeActive && !self.routePaused { return }
                if self.joystickActive && hypot(self.joystickVector.dx, self.joystickVector.dy) > 0.08 { return }
                _ = await self.apply(coordinate, pairing: pairing, epoch: epoch, markRecent: false)
            }
        }
    }

    private func pushRecent(_ coordinate: CLLocationCoordinate2D) {
        pushNamedRecent(
            name: Self.coordinateLabel(coordinate),
            coordinate: coordinate
        )
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        recents.removeAll {
            abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015
        }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func postDropNotification(_ message: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Locus spoof dropped")
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func offset(coordinate: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let earth = 6_378_137.0
        let latitude = max(-89.9999, min(89.9999, coordinate.latitude + northMeters / earth * (180 / .pi)))
        let scale = max(0.000001, cos(coordinate.latitude * .pi / 180))
        let longitude = (coordinate.longitude + eastMeters / (earth * scale) * (180 / .pi) + 540)
            .truncatingRemainder(dividingBy: 360) - 180
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
