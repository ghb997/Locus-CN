import Foundation

/// The scene and App Intents share the same main-actor session and library.
@MainActor
final class AppRuntime {
    static let shared = AppRuntime()
    let library: LibraryStore
    let pairing: PairingStore
    let session: SpoofSession
    let diagnostics = ConnectionDiagnostics()
    private init() {
        let library = LibraryStore()
        self.library = library
        pairing = PairingStore()
        session = SpoofSession(library: library)
    }
}
