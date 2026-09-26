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

/// Every native handle is confined to commands' serial queue. Public methods
/// enqueue synchronously, so Stop is a barrier even while a native call blocks.
enum LocationEngine {
    private static let commands = LocationCommandQueue()
    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var locationSimulation: OpaquePointer?

    static func beginSession() -> UUID { commands.beginSession() }

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String, generation: UUID,
                    completion: @escaping (Result<Void, LocationEngineError>) -> Void) {
        commands.perform(generation: generation, cancelled: .failure(LocationEngineError.cancelled), operation: {
            guard CoordinateMath.isValid(.init(latitude: latitude, longitude: longitude)) else { return .failure(.invalidCoordinate) }
            if let error = connectLocked(pairingPath: pairingPath, deviceIP: deviceIP) { return .failure(error) }
            // Stop can invalidate a session during the blocking tunnel handshake.
            guard commands.isCurrent(generation) else { return .failure(.cancelled) }
            if let error = location_simulation_set(locationSimulation, latitude, longitude) {
                let result = consume(error, stage: .locationSet)
                cleanup()
                return .failure(result)
            }
            return .success(())
        }, completion: completion)
    }

    static func clear(pairingPath: String, deviceIP: String, completion: @escaping (Result<Void, LocationEngineError>) -> Void) {
        commands.barrier(operation: {
            // The device can still be simulating after a connection was lost.
            if let error = connectLocked(pairingPath: pairingPath, deviceIP: deviceIP) { return .failure(error) }
            if let error = location_simulation_clear(locationSimulation) {
                let result = consume(error, stage: .locationClear)
                cleanup()
                return .failure(result)
            }
            cleanup()
            return .success(())
        }, completion: completion)
    }

    private static func consume(_ error: UnsafeMutablePointer<IdeviceFfiError>, stage: LocationEngineError) -> LocationEngineError {
        let code = Int32(error.pointee.code)
        idevice_error_free(error)
        // Raw pairing/tunnel diagnostics can contain credentials; retain only code.
        return .native(stage: stage.localizedDescription, code: code)
    }

    private static func cleanup() {
        if let handle = locationSimulation { location_simulation_free(handle); locationSimulation = nil }
        if let handle = remoteServer { remote_server_free(handle); remoteServer = nil }
        if let handle = handshake { rsd_handshake_free(handle); handshake = nil }
        if let handle = adapter { adapter_free(handle); adapter = nil }
    }

    private static func connectLocked(pairingPath: String, deviceIP: String) -> LocationEngineError? {
        if locationSimulation != nil { return nil }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else { return .invalidIP }

        var pairingHandle: OpaquePointer?
        if let error = pairingPath.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
            return consume(error, stage: .pairingRead)
        }
        guard let pairingHandle else { return .pairingRead }
        defer { rp_pairing_file_free(pairingHandle) }
        let tunnelError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing($0, socklen_t(MemoryLayout<sockaddr_in>.stride), "LocusLocation", pairingHandle, nil, nil, &adapter, &handshake)
            }
        }
        if let error = tunnelError {
            let result = consume(error, stage: .tunnelCreate)
            cleanup()
            return result
        }
        if let error = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            let result = consume(error, stage: .remoteServer)
            cleanup()
            return result
        }
        // LocationSimulationClient borrows RemoteServer; retain it until after
        // location_simulation_free, then release server, handshake and adapter.
        if let error = location_simulation_new(remoteServer, &locationSimulation) {
            let result = consume(error, stage: .simulationCreate)
            cleanup()
            return result
        }
        return nil
    }
}
