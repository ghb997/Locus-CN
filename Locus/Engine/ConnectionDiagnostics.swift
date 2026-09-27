import Foundation
import Network
import UIKit

struct DiagnosticStep: Identifiable {
    enum State { case waiting, running, passed, failed }
    let stage: ConnectionStage
    var state: State = .waiting
    var detail = ""
    var id: String { stage.rawValue }
}

@MainActor
final class ConnectionDiagnostics: ObservableObject {
    @Published private(set) var steps = ConnectionStage.allCases.map { DiagnosticStep(stage: $0) }
    @Published private(set) var isRunning = false
    @Published private(set) var cancellationRequested = false
    @Published private(set) var succeeded = false
    @Published private(set) var checkedAt: Date?
    private var task: Task<Void, Never>?

    func run(pairing: PairingStore) {
        guard !isRunning else { return }
        steps = ConnectionStage.allCases.map { DiagnosticStep(stage: $0) }
        isRunning = true; cancellationRequested = false; succeeded = false
        task = Task {
            defer { isRunning = false; checkedAt = Date() }
            do {
                mark(.pairing)
                pairing.refresh()
                guard pairing.hasPairingFile else { throw LocationEngineError.pairingRead }
                mark(.network)
                guard await Self.probeTCP(TunnelConfig.targetIP) else { throw LocationEngineError.tunnelCreate }
                try Task.checkCancellation()
                mark(.tunnel)
                let result: Result<Void, LocationEngineError> = await withCheckedContinuation { continuation in
                    LocationEngine.check(pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP, progress: { stage in
                        Task { @MainActor in if !self.cancellationRequested, stage != .pairing { self.mark(stage) } }
                    }, completion: { continuation.resume(returning: $0) })
                }
                try Task.checkCancellation()
                try result.get()
                for i in steps.indices { steps[i].state = .passed }
                succeeded = true
            } catch {
                if let index = steps.firstIndex(where: { $0.state == .running }) {
                    steps[index].state = .failed
                    steps[index].detail = cancellationRequested ? L10n.tr("Operation cancelled.") : error.localizedDescription
                }
            }
        }
    }
    func cancel() { cancellationRequested = true; task?.cancel() }
    private func mark(_ stage: ConnectionStage) {
        guard isRunning, !cancellationRequested else { return }
        for i in steps.indices where steps[i].state == .running { steps[i].state = .passed }
        if let index = steps.firstIndex(where: { $0.stage == stage }) { steps[index].state = .running }
    }
    func report() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let lines = steps.map { "\($0.stage.title): \($0.state)\($0.detail.isEmpty ? "" : " — " + $0.detail)" }
        return (["Locus \(version)", "iOS \(UIDevice.current.systemVersion)", checkedAt?.ISO8601Format() ?? "", L10n.tr("This report excludes pairing keys, coordinates and network addresses.")] + lines).joined(separator: "\n")
    }
    private static func probeTCP(_ ip: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.chrismack.locus.probe")
            let connection = NWConnection(host: NWEndpoint.Host(ip), port: 49152, using: .tcp)
            // Every completion and the timeout execute on this serial queue.
            var completed = false
            func finish(_ success: Bool) {
                guard !completed else { return }; completed = true
                connection.stateUpdateHandler = nil; connection.cancel(); continuation.resume(returning: success)
            }
            connection.stateUpdateHandler = { state in
                switch state { case .ready: finish(true); case .failed: finish(false); default: break }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { finish(false) }
        }
    }
}
