import SwiftUI

@main
struct LocusApp: App {
    @StateObject private var session = SpoofSession()
    @StateObject private var pairing = PairingStore()
    @AppStorage(SetupGate.defaultsKey) private var setupComplete = false

    /// Map when setup finished, or when already paired outside this walkthrough.
    private var showMap: Bool {
        setupComplete || (pairing.hasPairingFile && !SetupGate.isInProgress)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showMap {
                    RootView()
                } else {
                    SetupFlowView(initialStep: SetupGate.initialStep(hasPairingFile: pairing.hasPairingFile)) {
                        SetupGate.markComplete()
                        setupComplete = true
                    }
                }
            }
            .environmentObject(session)
            .environmentObject(pairing)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleIncoming(url)
            }
            .onAppear {
                if !setupComplete, pairing.hasPairingFile, !SetupGate.isInProgress {
                    SetupGate.markComplete()
                    setupComplete = true
                }
            }
        }
    }

    private func handleIncoming(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["plist", "mobiledevicepairing", "mobiledevicepair"].contains(ext) {
            guard session.canEditConnection else {
                session.lastError = L10n.tr("Stop location simulation before changing the pairing file.")
                return
            }
            do { try pairing.importPairing(from: url) }
            catch { session.lastError = error.localizedDescription }
        } else if ext == "gpx" {
            NotificationCenter.default.post(name: .locusImportGPX, object: url)
        }
    }
}

extension Notification.Name {
    static let locusImportGPX = Notification.Name("locusImportGPX")
}
