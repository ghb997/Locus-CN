import CoreLocation
import Darwin
import Foundation
import idevice

enum LocationEngineError: LocalizedError {
    case invalidIP, invalidCoordinate, pairingRead, tunnelCreate, remoteServer
    case simulationCreate, locationSet, locationClear, cancelled
    case native(stage: String, code: Int32)
    var errorDescription: String? {
        switch self {
        case .invalidIP: return L10n.tr("Tunnel IP is invalid. Check Settings → Tunnel IP (usually 10.7.0.1).")
        case .invalidCoordinate: return L10n.tr("Invalid coordinates. Latitude must be −90…90 and longitude −180…180.")
        case .pairingRead: return L10n.tr("Could not read the RPPairing file. Generate one with idevice_pair in RPPairing mode.")
        case .tunnelCreate: return L10n.tr("Could not open the developer tunnel. Is LocalDevVPN connected on Wi‑Fi?")
        case .remoteServer: return L10n.tr("Connected to the tunnel but RemoteXPC handshake failed.")
        case .simulationCreate: return L10n.tr("Could not open Apple’s location simulation service.")
        case .locationSet: return L10n.tr("Failed to set simulated coordinates.")
        case .locationClear: return L10n.tr("Failed to clear simulated location. Reconnect LocalDevVPN and try Stop again.")
        case .cancelled: return L10n.tr("Operation cancelled.")
        case .native(let stage, let code): return L10n.format("%@ (error %d)", stage, code)
        }
    }
}

enum ConnectionStage: String, CaseIterable, Identifiable {
    case pairing, network, tunnel, handshake, service
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pairing: return L10n.tr("Pairing record")
        case .network: return L10n.tr("Local network connection")
        case .tunnel: return L10n.tr("Tunnel and pair verification")
        case .handshake: return L10n.tr("Developer service handshake")
        case .service: return L10n.tr("Location simulation service")
        }
    }
}

/// Native ownership, including diagnostic connections, is confined to one serial queue.
enum LocationEngine {
    private static let commands = LocationCommandQueue()
    private static var connection: NativeConnection?
    static func beginSession() -> UUID { commands.beginSession() }
    static func discardConnection() { commands.barrier(operation: { connection = nil }, completion: { _ in }) }

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String, generation: UUID,
                    completion: @escaping (Result<Void, LocationEngineError>) -> Void) {
        commands.perform(generation: generation, cancelled: .failure(LocationEngineError.cancelled), operation: {
            guard CoordinateMath.isValid(.init(latitude: latitude, longitude: longitude)) else { return .failure(.invalidCoordinate) }
            if let error = connect(pairingPath, deviceIP) { return .failure(error) }
            guard commands.isCurrent(generation) else { return .failure(.cancelled) }
            if let error = location_simulation_set(connection!.simulation, latitude, longitude) {
                let result = consume(error, .locationSet); connection = nil; return .failure(result)
            }
            return .success(())
        }, completion: completion)
    }
    static func clear(pairingPath: String, deviceIP: String, completion: @escaping (Result<Void, LocationEngineError>) -> Void) {
        commands.barrier(operation: {
            if let error = connect(pairingPath, deviceIP) { return .failure(error) as Result<Void, LocationEngineError> }
            defer { connection = nil }
            if let error = location_simulation_clear(connection!.simulation) { return .failure(consume(error, .locationClear)) }
            return .success(())
        }, completion: completion)
    }
    static func check(pairingPath: String, deviceIP: String, progress: @escaping (ConnectionStage) -> Void,
                      completion: @escaping (Result<Void, LocationEngineError>) -> Void) {
        commands.barrier(operation: {
            let probe = NativeConnection()
            // This isolated connection never calls location_simulation_set/clear.
            if let error = probe.open(pairingPath, deviceIP, progress: progress) { return .failure(error) as Result<Void, LocationEngineError> }
            return .success(())
        }, completion: completion)
    }
    private static func connect(_ path: String, _ ip: String) -> LocationEngineError? {
        if let current = connection, current.path == path, current.ip == ip { return nil }
        connection = nil
        let candidate = NativeConnection()
        if let error = candidate.open(path, ip, progress: { _ in }) { return error }
        connection = candidate
        return nil
    }
    fileprivate static func consume(_ error: UnsafeMutablePointer<IdeviceFfiError>, _ stage: LocationEngineError) -> LocationEngineError {
        let code = Int32(error.pointee.code); idevice_error_free(error)
        return .native(stage: stage.localizedDescription, code: code)
    }
}

private final class NativeConnection {
    var adapter: OpaquePointer?, handshake: OpaquePointer?, server: OpaquePointer?, simulation: OpaquePointer?
    var path = "", ip = ""
    deinit {
        if let simulation { location_simulation_free(simulation) }
        if let server { remote_server_free(server) }
        if let handshake { rsd_handshake_free(handshake) }
        if let adapter { adapter_free(adapter) }
    }
    func open(_ path: String, _ ip: String, progress: (ConnectionStage) -> Void) -> LocationEngineError? {
        self.path = path; self.ip = ip
        // Native API timeout; several stages may each consume this interval.
        // Never free an in-flight handle to pretend that a call was cancelled.
        idevice_set_global_timeout(15)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        guard ip.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else { return .invalidIP }
        progress(.pairing)
        var pairing: OpaquePointer?
        if let error = path.withCString({ rp_pairing_file_read($0, &pairing) }) { return LocationEngine.consume(error, .pairingRead) }
        guard let pairing else { return .pairingRead }
        defer { rp_pairing_file_free(pairing) }
        progress(.tunnel)
        let failure = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing($0, socklen_t(MemoryLayout<sockaddr_in>.stride), "LocusLocation", pairing, nil, nil, &adapter, &handshake)
            }
        }
        if let failure { return LocationEngine.consume(failure, .tunnelCreate) }
        progress(.handshake)
        if let failure = remote_server_connect_rsd(adapter, handshake, &server) { return LocationEngine.consume(failure, .remoteServer) }
        progress(.service)
        if let failure = location_simulation_new(server, &simulation) { return LocationEngine.consume(failure, .simulationCreate) }
        return nil
    }
}
