import CoreLocation
import Foundation
import MapKit
import UIKit

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive
    var id: String { rawValue }
    var title: String {
        switch self { case .walk: return L10n.tr("Walk"); case .run: return L10n.tr("Run"); case .cycle: return L10n.tr("Cycle"); case .drive: return L10n.tr("Drive") }
    }
    var icon: String {
        switch self { case .walk: return "figure.walk"; case .run: return "figure.run"; case .cycle: return "bicycle"; case .drive: return "car.fill" }
    }
    var baseSpeed: CLLocationSpeed {
        switch self { case .walk: return 1.4; case .run: return 3.3; case .cycle: return 6.5; case .drive: return 13.4 }
    }
    var mkTransportType: MKDirectionsTransportType {
        switch self { case .walk, .run: return .walking; case .cycle, .drive: return .automobile }
    }
}

enum SpoofStatus: Equatable {
    case idle, connecting, active, reconnecting, stopping
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
    var isDropped: Bool { if case .dropped = self { return true }; return false }
}

enum SessionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published private(set) var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published private(set) var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    @Published var mapStyleIndex = 0
    @Published var lastError: String?
    @Published private(set) var isBusy = false
    @Published private(set) var joystickActive = false
    @Published private(set) var routeActive = false
    @Published private(set) var routePaused = false
    @Published private(set) var routeProgress = 0.0
    @Published private(set) var routeRemainingMeters = 0.0
    @Published private(set) var routeRemainingSeconds = 0.0
    @Published private(set) var lastCommandAt: Date?
    @Published private(set) var recovery: SessionCheckpoint?
    @Published private(set) var reconnectAttempt = 0
    @Published var speedMultiplier = 1.0
    let library: LibraryStore
    private let locationKeeper = BackgroundKeepAlive()
    private var generation = LocationEngine.beginSession()
    private var movementTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var resendTimer: Timer?
    private var joystickVector: CGVector = .zero
    private var movementClock = MovementClock()
    private var activeRoute: SavedRoute?
    private var routeElapsed = 0.0
    private var lastSaveUptime = 0.0
    private var lastACKUptime: Double?
    private var routeSpeed = 0.0

    init(library: LibraryStore) {
        self.library = library
        if SessionRecoveryStore.needsRestore {
            recovery = SessionRecoveryStore.load()
            simulated = recovery?.coordinate.coordinate
            pin = simulated
            status = .dropped(L10n.tr("An earlier session may still be active. Choose how to recover."))
        }
    }
    var isSpoofing: Bool { status == .active }
    var canStop: Bool { status != .idle || SessionRecoveryStore.needsRestore }
    var isStopping: Bool { status == .stopping }
    var canEditConnection: Bool { !isBusy && status != .reconnecting && (status == .idle || status.isDropped) }
    var systemCoordinate: CLLocationCoordinate2D? { locationKeeper.lastKnownCoordinate }
    var displayedSpeed: Double { routeActive ? routeSpeed : travelMode.baseSpeed * speedMultiplier }
    var canResumeRoute: Bool { recovery?.route != nil }
    var favorites: [SavedPlace] { library.favorites }
    var recents: [SavedPlace] { library.recents }

    func startLocationUpdates() { locationKeeper.requestFreshLocation { [weak self] error in self?.lastError = error } }
    func freshSystemCoordinate() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            locationKeeper.requestFreshLocation { [weak self] error in
                if let error { self?.lastError = error }
                continuation.resume(returning: self?.locationKeeper.lastKnownCoordinate)
            }
        }
    }
    private func ready(_ pairing: PairingStore) throws {
        guard !isStopping else { throw SessionError.message(L10n.tr("Wait for Stop to finish before starting another action.")) }
        pairing.refresh()
        guard pairing.hasPairingFile else { throw SessionError.message(L10n.tr("Import an RPPairing file in Settings first.")) }
    }
    @discardableResult
    private func beginMovement() -> UUID {
        generation = LocationEngine.beginSession()
        movementTask?.cancel(); reconnectTask?.cancel()
        movementTask = nil; actionTask = nil; reconnectTask = nil
        resendTimer?.invalidate(); resendTimer = nil
        joystickActive = false; joystickVector = .zero
        routeActive = false; routePaused = false; routeProgress = 0
        routeRemainingMeters = 0; routeRemainingSeconds = 0
        activeRoute = nil; routeElapsed = 0; movementClock.reset()
        isBusy = false; reconnectAttempt = 0
        return generation
    }
    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore, name: String? = nil) {
        guard !isStopping else { return }
        actionTask = Task { do { try await teleportAndWait(to: coordinate, pairing: pairing, name: name) } catch { if !(error is CancellationError) { lastError = error.localizedDescription } } }
    }
    func teleportAndWait(to coordinate: CLLocationCoordinate2D, pairing: PairingStore, name: String? = nil) async throws {
        try ready(pairing)
        guard CoordinateMath.isValid(coordinate) else { throw LocationEngineError.invalidCoordinate }
        // The caller task is not stored until after this epoch change.
        let epoch = beginMovement()
        pin = coordinate
        try await apply(coordinate, pairing: pairing, epoch: epoch)
        library.record(SavedPlace(name: name ?? CoordinateConverter.label(coordinate), latitude: coordinate.latitude, longitude: coordinate.longitude), search: false)
        persist(force: true)
    }
    func stop(pairing: PairingStore) { beginStop(pairing: pairing, completion: { _ in }) }
    func stopAndWait(pairing: PairingStore) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            beginStop(pairing: pairing) { continuation.resume(with: $0) }
        }
    }
    private func beginStop(pairing: PairingStore, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isStopping else { completion(.failure(SessionError.message(L10n.tr("Wait for Stop to finish before starting another action.")))); return }
        let epoch = beginMovement()
        // Invalidate recovery BEFORE the native clear. A failed clear is retryable,
        // but may never revive a previous movement source.
        recovery = nil; SessionRecoveryStore.remove(); SessionRecoveryStore.needsRestore = true
        status = .stopping; isBusy = true; locationKeeper.stopSession()
        LocationEngine.clear(pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP) { result in
            Task { @MainActor in
                guard self.generation == epoch else { completion(.failure(CancellationError())); return }
                self.isBusy = false
                switch result {
                case .success:
                    SessionRecoveryStore.needsRestore = false
                    self.simulated = nil; self.status = .idle; self.lastError = nil
                    self.lastCommandAt = nil; self.lastACKUptime = nil
                    self.locationKeeper.resetLastLocation()
                    self.startLocationUpdates()
                    completion(.success(()))
                case .failure(let error):
                    self.status = .dropped(error.localizedDescription); self.lastError = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    func startRoute(_ route: SavedRoute, pairing: PairingStore, elapsed: Double = 0) {
        guard !isStopping else { return }
        actionTask = Task {
            do { try await startRouteAndWait(route, pairing: pairing, elapsed: elapsed) }
            catch { if !(error is CancellationError) { lastError = error.localizedDescription } }
        }
    }
    func startRouteAndWait(_ route: SavedRoute, pairing: PairingStore, elapsed: Double = 0) async throws {
        try ready(pairing)
        let timeline = try RouteTimeline(route: route)
        let epoch = beginMovement()
        activeRoute = route; routeElapsed = min(timeline.duration, max(0, elapsed))
        routeSpeed = route.options.metersPerSecond
        let first = timeline.sample(at: routeElapsed)
        try await apply(first.coordinate, pairing: pairing, epoch: epoch)
        routeActive = routeElapsed < timeline.duration
        updateProgress(timeline)
        persist(force: true)
        movementClock.reset(at: ProcessInfo.processInfo.systemUptime)
        movementTask = Task { [weak self] in
            guard let self else { return }
            while self.generation == epoch, !Task.isCancelled, self.routeActive {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                let step = self.movementClock.step(at: ProcessInfo.processInfo.systemUptime, advancing: !self.routePaused && !self.isBusy)
                if step.suspended {
                    self.routePaused = true; self.persist(force: true)
                    self.lastError = L10n.tr("Movement paused after a long delay. Resume explicitly to avoid a position jump.")
                    continue
                }
                guard step.seconds > 0, !self.routePaused, !self.isBusy else { continue }
                let nextElapsed = min(timeline.duration, self.routeElapsed + step.seconds)
                do { try await self.apply(timeline.sample(at: nextElapsed).coordinate, pairing: pairing, epoch: epoch) }
                catch { return }
                self.routeElapsed = nextElapsed
                self.updateProgress(timeline)
                if nextElapsed >= timeline.duration { self.routeActive = false; self.activeRoute = nil }
                self.persist(force: !self.routeActive)
            }
        }
    }
    private func updateProgress(_ timeline: RouteTimeline) {
        let sample = timeline.sample(at: routeElapsed)
        routeProgress = sample.progress; routeRemainingMeters = sample.remainingMeters
        routeRemainingSeconds = max(0, timeline.duration - routeElapsed)
    }
    func toggleRoutePause() {
        guard routeActive, status == .active else { return }
        routePaused.toggle(); movementClock.reset(at: ProcessInfo.processInfo.systemUptime); persist(force: true)
    }
    func resumeSavedRoute(pairing: PairingStore) {
        guard let checkpoint = recovery, let route = checkpoint.route else { return }
        startRoute(route, pairing: pairing, elapsed: checkpoint.elapsed)
    }
    func holdLastPosition(pairing: PairingStore) {
        guard let coordinate = recovery?.coordinate.coordinate ?? simulated else { return }
        teleport(to: coordinate, pairing: pairing)
    }
    func startJoystick(pairing: PairingStore) {
        guard !isStopping else { return }
        do { try ready(pairing) } catch { lastError = error.localizedDescription; return }
        guard let start = simulated ?? pin ?? systemCoordinate else { lastError = L10n.tr("Drop a pin or teleport somewhere before using the joystick."); return }
        let epoch = beginMovement()
        joystickActive = true
        actionTask = Task {
            do { try await apply(start, pairing: pairing, epoch: epoch) } catch { return }
            persist(force: true)
            movementClock.reset(at: ProcessInfo.processInfo.systemUptime)
            movementTask = Task {
                while generation == epoch, !Task.isCancelled, joystickActive {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                    let magnitude = hypot(joystickVector.dx, joystickVector.dy)
                    let step = movementClock.step(at: ProcessInfo.processInfo.systemUptime, advancing: magnitude > 0.08 && !isBusy)
                    if step.suspended { updateJoystick(vector: .zero); continue }
                    guard step.seconds > 0, magnitude > 0.08, let current = simulated, !isBusy else { continue }
                    let meters = displayedSpeed * min(1, Double(magnitude)) * step.seconds
                    let next = CoordinateMath.offset(current, eastMeters: Double(joystickVector.dx / magnitude) * meters, northMeters: Double(-joystickVector.dy / magnitude) * meters)
                    do { try await apply(next, pairing: pairing, epoch: epoch) } catch { return }
                    persist()
                }
            }
        }
    }
    func updateJoystick(vector: CGVector) {
        if hypot(joystickVector.dx, joystickVector.dy) <= 0.08 || vector == .zero { movementClock.reset(at: ProcessInfo.processInfo.systemUptime) }
        joystickVector = vector
    }
    func stopJoystick() {
        joystickActive = false; joystickVector = .zero; movementTask?.cancel(); movementTask = nil
        persist(force: true)
    }
    func sceneChanged(active: Bool, background: Bool) {
        updateJoystick(vector: .zero)
        if background {
            library.flush(); persist(force: true)
            if !UserDefaults.standard.bool(forKey: "locus.backgroundEnabled"), routeActive {
                routePaused = true; movementClock.reset()
            }
        }
        guard active, status == .active, let last = lastACKUptime,
              ProcessInfo.processInfo.systemUptime - last > 12 else { return }
        markDropped(L10n.tr("The session has not been confirmed recently. Check the connection before continuing."))
        LocationEngine.discardConnection()
    }
    func reconnect(pairing: PairingStore) {
        guard status.isDropped, !isBusy else { return }
        reconnectTask?.cancel()
        let epoch = generation
        status = .reconnecting; reconnectAttempt = 0
        LocationEngine.discardConnection()
        reconnectTask = Task {
            for delay in [1, 2, 4] {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard generation == epoch, !Task.isCancelled else { return }
                reconnectAttempt += 1
                let result: Result<Void, LocationEngineError> = await withCheckedContinuation { continuation in
                    LocationEngine.check(pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP, progress: { _ in }) { continuation.resume(returning: $0) }
                }
                guard generation == epoch, !Task.isCancelled else { return }
                if case .success = result {
                    status = .dropped(L10n.tr("Connection checked. Choose Hold position or Continue route."))
                    return
                }
                if case .failure(let error) = result, reconnectAttempt == 3 {
                    status = .dropped(error.localizedDescription); lastError = error.localizedDescription
                }
            }
        }
    }
    func cancelReconnect() {
        reconnectTask?.cancel(); reconnectTask = nil
        if status == .reconnecting { status = .dropped(L10n.tr("Operation cancelled.")) }
    }
    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, epoch: UUID) async throws {
        guard generation == epoch, !Task.isCancelled, !isStopping else { throw CancellationError() }
        if status == .idle || status.isDropped { status = .connecting }
        isBusy = true
        // Even a lost response may have applied a location on the device.
        SessionRecoveryStore.needsRestore = true
        let result: Result<Void, LocationEngineError> = await withCheckedContinuation { continuation in
            LocationEngine.set(latitude: coordinate.latitude, longitude: coordinate.longitude, pairingPath: pairing.pairingPath,
                               deviceIP: TunnelConfig.targetIP, generation: epoch) { continuation.resume(returning: $0) }
        }
        guard generation == epoch else { throw CancellationError() }
        isBusy = false
        switch result {
        case .success:
            simulated = coordinate; status = .active; lastError = nil
            lastCommandAt = Date(); lastACKUptime = ProcessInfo.processInfo.systemUptime
            locationKeeper.startSession(backgroundEnabled: UserDefaults.standard.bool(forKey: "locus.backgroundEnabled"))
            startResend(pairing: pairing, epoch: epoch)
        case .failure(.cancelled): throw CancellationError()
        case .failure(let error): markDropped(error.localizedDescription); throw error
        }
    }
    private func markDropped(_ reason: String) {
        status = .dropped(reason); lastError = reason
        routePaused = routeActive; joystickActive = false; joystickVector = .zero
        persist(force: true); movementTask?.cancel(); movementTask = nil
        resendTimer?.invalidate(); resendTimer = nil; locationKeeper.stopSession()
    }
    private func startResend(pairing: PairingStore, epoch: UUID) {
        guard resendTimer == nil else { return }
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == epoch, self.status == .active, !self.isBusy,
                      let coordinate = self.simulated else { return }
                if self.routeActive && !self.routePaused { return }
                if self.joystickActive && hypot(self.joystickVector.dx, self.joystickVector.dy) > 0.08 { return }
                do { try await self.apply(coordinate, pairing: pairing, epoch: epoch) } catch { return }
            }
        }
    }
    private func persist(force: Bool = false) {
        guard let coordinate = simulated, !isStopping, SessionRecoveryStore.needsRestore else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastSaveUptime >= 2 else { return }
        let checkpoint = SessionCheckpoint(coordinate: RoutePoint(coordinate), route: activeRoute, elapsed: routeElapsed)
        do { try SessionRecoveryStore.save(checkpoint); recovery = checkpoint; lastSaveUptime = now }
        catch { lastError = L10n.tr("The session checkpoint could not be saved. Recovery after closing the app may be unavailable.") }
    }
    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        library.addFavorite(SavedPlace(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        fallback ?? library.favorites.first(where: { $0.id == SavedPlace(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude).id })?.name ?? CoordinateConverter.label(coordinate)
    }
}
