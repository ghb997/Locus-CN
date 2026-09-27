import AppIntents
import Foundation

struct LocusPlaceEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Saved place")
    static var defaultQuery = LocusPlaceQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct LocusPlaceQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [LocusPlaceEntity] {
        AppRuntime.shared.library.favorites.filter { identifiers.contains($0.id) }.map { .init(id: $0.id, name: $0.name) }
    }
    @MainActor func suggestedEntities() async throws -> [LocusPlaceEntity] {
        AppRuntime.shared.library.favorites.map { .init(id: $0.id, name: $0.name) }
    }
}
struct LocusRouteEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Saved route")
    static var defaultQuery = LocusRouteQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct LocusRouteQuery: EntityQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [LocusRouteEntity] {
        AppRuntime.shared.library.routes.filter { identifiers.contains($0.id) }.map { .init(id: $0.id, name: $0.name) }
    }
    @MainActor func suggestedEntities() async throws -> [LocusRouteEntity] {
        AppRuntime.shared.library.routes.map { .init(id: $0.id, name: $0.name) }
    }
}
struct TeleportPlaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Teleport to saved place"
    static var description = IntentDescription("Open Locus and start location simulation at a saved place.")
    static var openAppWhenRun = true
    @Parameter(title: "Saved place") var place: LocusPlaceEntity
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = AppRuntime.shared
        guard let saved = runtime.library.favorites.first(where: { $0.id == place.id }) else {
            throw SessionError.message(L10n.tr("The saved item no longer exists. Choose another item in Shortcuts."))
        }
        try await runtime.session.teleportAndWait(to: saved.coordinate, pairing: runtime.pairing, name: saved.name)
        return .result(dialog: "Location command accepted.")
    }
}
struct StartSavedRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "Start saved route"
    static var description = IntentDescription("Open Locus and start a saved route using its playback settings.")
    static var openAppWhenRun = true
    @Parameter(title: "Saved route") var route: LocusRouteEntity
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = AppRuntime.shared
        guard let saved = runtime.library.routes.first(where: { $0.id == route.id }) else {
            throw SessionError.message(L10n.tr("The saved item no longer exists. Choose another item in Shortcuts."))
        }
        try await runtime.session.startRouteAndWait(saved, pairing: runtime.pairing)
        return .result(dialog: "Route started. Its first location command was accepted.")
    }
}
struct RestoreLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "Restore system location"
    static var description = IntentDescription("Stop movement and clear the current location simulation.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = AppRuntime.shared
        try await runtime.session.stopAndWait(pairing: runtime.pairing)
        return .result(dialog: "Simulation cleared. Wait for a fresh system location.")
    }
}
struct LocusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TeleportPlaceIntent(), phrases: ["Teleport with \(.applicationName)"], shortTitle: "Teleport", systemImageName: "location.fill")
        AppShortcut(intent: StartSavedRouteIntent(), phrases: ["Start a route with \(.applicationName)"], shortTitle: "Start route", systemImageName: "point.topleft.down.to.point.bottomright.curvepath")
        AppShortcut(intent: RestoreLocationIntent(), phrases: ["Restore location with \(.applicationName)"], shortTitle: "Restore location", systemImageName: "stop.circle")
    }
}
