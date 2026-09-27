import SwiftUI

@main
struct LocusApp: App {
    @StateObject private var session = AppRuntime.shared.session
    @StateObject private var pairing = AppRuntime.shared.pairing
    @StateObject private var library = AppRuntime.shared.library
    @StateObject private var diagnostics = AppRuntime.shared.diagnostics
    @AppStorage("locus.appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
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
            .environmentObject(library)
            .environmentObject(diagnostics)
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .onChange(of: scenePhase) { _, phase in session.sceneChanged(active: phase == .active, background: phase == .background) }
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
            library.incomingGPX = url
        }
    }
}

extension Notification.Name {
    static let locusImportGPX = Notification.Name("locusImportGPX")
}
