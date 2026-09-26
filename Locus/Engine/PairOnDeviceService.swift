import Foundation
import Darwin
import idevice
import UIKit
import UserNotifications
import CoreLocation

/// Runs idevice's iOS 27+ pairable-host flow on-device.
///
/// Advertising uses Network.framework NWListener (Bonjour). Inbound TCP is
/// relayed to the Rust pairable-host on loopback. The 6-digit PIN is created
/// only after that connection + pair-setup handshake.
@MainActor
final class PairOnDeviceService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case advertising
        case deviceConnected
        case awaitingPIN(String)
        case succeeded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pin: String?
    @Published private(set) var debugPort: UInt16?

    private var worker: Thread?
    private var callbackBox = PairCallbackBox()
    private weak var pairingStore: PairingStore?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private let keepAlive = PairingKeepAlive()
    private let audioKeepAlive = SilentAudioKeepAlive()
    private let advertiser = PairableHostAdvertiser()

    var isBusy: Bool {
        switch phase {
        case .advertising, .deviceConnected, .awaitingPIN: return true
        default: return false
        }
    }

    func start(pairingStore: PairingStore) {
        guard !isBusy else { return }
        phase = .advertising
        pin = nil
        debugPort = nil
        callbackBox.owner = nil
        callbackBox = PairCallbackBox()
        callbackBox.owner = self
        self.pairingStore = pairingStore

        requestNotificationPermission()
        beginKeepAlive()

        _ = pairingStore.pairingURL
        try? FileManager.default.createDirectory(
            at: pairingStore.pairingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let box = callbackBox

        worker = Thread {
            autoreleasepool {
                Self.runBlockingAccept(box: box)
            }
        }
        worker?.name = "locus.pairable-host"
        worker?.qualityOfService = .userInitiated
        worker?.start()
    }

    func acknowledgeFailure() {
        if case .failed = phase {
            teardown()
            phase = .idle
            pin = nil
        }
    }

    func resetToIdle() {
        teardown()
        phase = .idle
        pin = nil
        debugPort = nil
    }

    fileprivate func handleListening(
        port: UInt16,
        serviceIdentifier: String,
        name: String,
        model: String,
        authTag: String,
        ver: String,
        minVer: String
    ) {
        debugPort = port
        advertiser.publish(
            port: port,
            serviceIdentifier: serviceIdentifier,
            name: name,
            model: model,
            authTag: authTag,
            ver: ver,
            minVer: minVer
        )
        phase = .advertising
        NSLog("[Locus] listening on %u, Bonjour id=%@", port, serviceIdentifier)
    }

    fileprivate func handleConnected() {
        phase = .deviceConnected
        Self.postPlainNotification(
            title: L10n.tr("Locus connected"),
            body: L10n.tr("Generating pairing code…")
        )
    }

    fileprivate func handlePIN(_ value: String) {
        pin = value
        phase = .awaitingPIN(value)
        Self.postPINNotification(value)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    fileprivate func handleSuccess() {
        pin = nil
        phase = .succeeded
        teardown()
        Self.postPlainNotification(
            title: L10n.tr("Locus paired"),
            body: L10n.tr("RPPairing is ready. Connect LocalDevVPN, then teleport.")
        )
    }

    fileprivate func handleFailure(_ message: String) {
        pin = nil
        phase = .failed(message)
        teardown()
    }

    private func installPairingData(_ data: Data) {
        do {
            guard let pairingStore else { return }
            try pairingStore.installPairingData(data)
            handleSuccess()
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    private func teardown() {
        callbackBox.owner = nil
        callbackBox.cancel()
        advertiser.stop()
        endKeepAlive()
    }

    private func beginKeepAlive() {
        UIApplication.shared.isIdleTimerDisabled = true
        keepAlive.start()
        audioKeepAlive.start()
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "locus.pairable-host") { [weak self] in
            self?.endKeepAlive()
        }
    }

    private func endKeepAlive() {
        UIApplication.shared.isIdleTimerDisabled = false
        keepAlive.stop()
        audioKeepAlive.stop()
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func postPINNotification(_ pin: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Locus pairing code")
        content.body = pin
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(identifier: "locus.pairing.pin", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func postPlainNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "locus.pairing.status.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private nonisolated static func runBlockingAccept(box: PairCallbackBox) {
        // The current idevice API lets iOS own Bonjour and the accepted socket.
        // This replaces the upstream app's unversioned, custom callback ABI.
        var host: OpaquePointer?
        var serviceID: UnsafeMutablePointer<CChar>?
        var txtBytes: UnsafeMutablePointer<UInt8>?
        var txtLength: UInt = 0
        var hostIRK = [UInt8](repeating: 0, count: 16)
        let error = pairable_host_prepare("Locus", "Mac17,7", false, &host, &serviceID, &txtBytes, &txtLength, &hostIRK)
        if let error {
            report(error, box: box)
            return
        }
        guard let host, let serviceID, let txtBytes else { return }
        defer {
            pairable_host_free(host)
            idevice_string_free(serviceID)
            idevice_data_free(txtBytes, txtLength)
        }
        let service = String(cString: serviceID)
        let txtData = Data(bytes: txtBytes, count: Int(txtLength))
        guard let txt = (try? PropertyListSerialization.propertyList(from: txtData, options: [], format: nil)) as? [String: String] else { return }

        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { reportSocketFailure(box); return }
        box.track(listener)
        defer { box.closeSocket(listener) }
        guard !box.isCancelled else { return }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(listener, 1) == 0 else { reportSocketFailure(box); return }
        var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let located = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(listener, $0, &addressLength)
            }
        }
        guard located == 0 else { reportSocketFailure(box); return }
        let port = UInt16(bigEndian: address.sin_port)
        DispatchQueue.main.async {
            box.owner?.handleListening(port: port, serviceIdentifier: service,
                name: txt["name"] ?? "Locus", model: txt["model"] ?? "Mac17,7",
                authTag: txt["authTag"] ?? "", ver: txt["ver"] ?? "26", minVer: txt["minVer"] ?? "17")
        }

        var socket: Int32 = -1
        while !box.isCancelled {
            var event = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&event, 1, 200)
            guard !box.isCancelled else { return }
            if ready < 0 {
                if errno == EINTR { continue }
                reportSocketFailure(box)
                return
            }
            if ready == 0 { continue }
            socket = Darwin.accept(listener, nil, nil)
            break
        }
        guard socket >= 0 else {
            if !box.isCancelled { reportSocketFailure(box) }
            return
        }
        box.track(socket)
        defer { box.closeSocket(socket) }
        guard !box.isCancelled else { return }
        DispatchQueue.main.async { box.owner?.handleConnected() }

        var file: OpaquePointer?
        if let error = pairable_host_accept_fd(host, socket, pinDisplayTrampoline,
                                               Unmanaged.passUnretained(box).toOpaque(), nil, &file) {
            report(error, box: box)
            return
        }
        guard let file else { return }
        defer { rp_pairing_file_free(file) }
        var bytes: UnsafeMutablePointer<UInt8>?
        var length: UInt = 0
        if let error = rp_pairing_file_to_bytes(file, &bytes, &length) {
            report(error, box: box)
            return
        }
        guard let bytes else { return }
        defer { idevice_data_free(bytes, length) }
        let data = Data(bytes: bytes, count: Int(length))
        do {
            guard var plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return }
            // Persist the host identity returned by pairable_host_prepare.
            if plist["alt_irk"] == nil { plist["alt_irk"] = Data(hostIRK) }
            let record = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            DispatchQueue.main.async { box.owner?.installPairingData(record) }
        } catch {
            DispatchQueue.main.async { box.owner?.handleFailure(L10n.tr("Failed to write pairing file")) }
        }
    }

    private nonisolated static func report(_ error: UnsafeMutablePointer<IdeviceFfiError>, box: PairCallbackBox) {
        let message = L10n.format("Pairing failed (error %d). Check Developer Mode and Local Network permissions.", Int32(error.pointee.code))
        idevice_error_free(error)
        DispatchQueue.main.async { box.owner?.handleFailure(message) }
    }

    private nonisolated static func reportSocketFailure(_ box: PairCallbackBox) {
        let message = L10n.format("Pairing failed (error %d). Check Developer Mode and Local Network permissions.", errno)
        DispatchQueue.main.async { box.owner?.handleFailure(message) }
    }
}

private final class PairingKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func start() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }
}

final class PairCallbackBox: @unchecked Sendable {
    // Read and written only on the main queue by the owner / dispatched callbacks.
    weak var owner: PairOnDeviceService?
    private let lock = NSLock()
    private var cancelled = false
    private var sockets: Set<Int32> = []

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func track(_ socket: Int32) {
        lock.lock()
        defer { lock.unlock() }
        sockets.insert(socket)
        if cancelled { Darwin.shutdown(socket, SHUT_RDWR) }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        // shutdown also wakes the descriptor duplicated by the native handshake.
        // The worker owns close(), so a recycled descriptor cannot be closed here.
        for socket in sockets { Darwin.shutdown(socket, SHUT_RDWR) }
    }

    func closeSocket(_ socket: Int32) {
        lock.lock()
        defer { lock.unlock() }
        sockets.remove(socket)
        Darwin.close(socket)
    }
}

private func pinDisplayTrampoline(pin: UnsafePointer<CChar>?, context: UnsafeMutableRawPointer?) {
    guard let pin, let context else { return }
    let value = String(cString: pin)
    let box = Unmanaged<PairCallbackBox>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { box.owner?.handlePIN(value) }
}

