import SwiftUI
import UniformTypeIdentifiers

struct RoutePlannerSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @State private var history: [SavedRoute] = []
    @State private var buildTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var isRouting = false
    @State private var showCoordinate = false
    @State private var editingPoint: RoutePoint?
    @State private var showImporter = false
    @State private var importing = false
    @State private var imported: GPXSelection?
    @State private var shared: SharedFile?
    @State private var error: String?
    @State private var showNewConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("Route draft")) {
                    TextField(L10n.tr("Route name"), text: $library.draft.name)
                    Picker(L10n.tr("Route type"), selection: $library.draft.kind) {
                        ForEach(RouteKind.allCases) { Text($0.title).tag($0) }
                    }
                    if library.draft.kind != .gpx {
                        waypointRows
                        Button(L10n.tr("Add current pin")) {
                            guard let point = session.pin ?? session.simulated else { error = L10n.tr("Tap the map to drop a pin first."); return }
                            remember(); library.draft.waypoints.append(RoutePoint(point)); invalidatePath()
                        }.disabled(library.draft.waypoints.count >= 200)
                        Button(L10n.tr("Add coordinates")) { showCoordinate = true }
                            .disabled(library.draft.waypoints.count >= 200)
                    } else {
                        Text(L10n.format("%d points · %.1f km", library.draft.path.count, CoordinateMath.length(library.draft.path.map(\.coordinate)) / 1000))
                        Text(L10n.tr("GPX timestamps, point names and elevation are preserved. The location engine sends latitude and longitude only."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(L10n.tr("Undo route edit")) {
                            if let previous = history.popLast() { cancelBuild(); library.draft = previous }
                        }.disabled(history.isEmpty)
                        Spacer()
                        Button(L10n.tr("New route"), role: .destructive) { showNewConfirmation = true }
                    }
                }
                playbackSection
                Section {
                    if library.draft.kind == .road {
                        Button {
                            if isRouting { cancelBuild() } else { buildRoad() }
                        } label: {
                            HStack { Text(isRouting ? L10n.tr("Cancel route planning") : L10n.tr("Build road route")); if isRouting { ProgressView() } }
                        }
                        Text(L10n.tr("Walking and running use walking directions. Cycling and driving use automobile directions; cycling-specific directions are unavailable."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let timeline = try? RouteTimeline(route: library.draft) {
                        Text(L10n.format("%.1f km · %.0f min", timeline.distance / 1000, timeline.duration / 60))
                    }
                    Button(L10n.tr("Play route")) {
                        do { _ = try RouteTimeline(route: library.draft); session.startRoute(library.draft, pairing: pairing); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(isRouting || session.isStopping)
                    Button(L10n.tr("Save route")) {
                        do { try library.saveDraft() } catch { self.error = error.localizedDescription }
                    }.disabled(isRouting)
                }
                Section(L10n.tr("Route library")) {
                    if library.routes.isEmpty { Text(L10n.tr("Saved routes appear here.")).foregroundStyle(.secondary) }
                    ForEach(library.routes) { route in
                        Button {
                            remember(); cancelBuild(); library.draft = route
                        } label: {
                            VStack(alignment: .leading) {
                                Text(route.name)
                                Text(L10n.format("%d points · %.1f km", route.playbackPoints.count, CoordinateMath.length(route.playbackPoints.map(\.coordinate)) / 1000))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.swipeActions {
                            Button(L10n.tr("Delete"), role: .destructive) { library.deleteRoute(route) }
                        }
                    }
                }
                Section(L10n.tr("GPX")) {
                    Button(L10n.tr("Import GPX…")) { showImporter = true }.disabled(importing)
                    Button(L10n.tr("Export GPX…")) { exportGPX() }
                    if importing { ProgressView(L10n.tr("Reading GPX…")) }
                    Text(L10n.tr("GPX export uses WGS-84 and preserves available point metadata. Playback speed, repetitions and dwell settings are saved in the JSON backup."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.tr("Routes"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("Done")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
            .sheet(isPresented: $showCoordinate) {
                CoordinateEntryView(initial: nil) { point in remember(); library.draft.waypoints.append(point); invalidatePath() }
            }
            .sheet(item: $editingPoint) { point in
                WaypointEditor(point: point) { edited in
                    guard let index = library.draft.waypoints.firstIndex(where: { $0.id == edited.id }) else { return }
                    remember(); library.draft.waypoints[index] = edited; invalidatePath()
                }
            }
            .sheet(item: $imported) { selection in
                GPXSelectionView(segments: selection.segments) { segment, source in
                    remember(); cancelBuild()
                    var route = SavedRoute(); route.kind = .gpx; route.name = segment.name
                    route.path = segment.points.map {
                        var point = $0
                        let converted = CoordinateConverter.convert(point.coordinate, from: source, to: .wgs84)
                        point.latitude = converted.latitude; point.longitude = converted.longitude
                        return point
                    }
                    library.draft = route; session.pin = route.path.first?.coordinate
                }
            }
            .sheet(item: $shared) { FileShareSheet(url: $0.url) }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.xml, .data]) { result in
                switch result { case .success(let url): importGPX(url); case .failure(let failure): error = failure.localizedDescription }
            }
            .alert("Locus", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L10n.tr("OK"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .confirmationDialog(L10n.tr("Replace the current draft with a new route?"), isPresented: $showNewConfirmation, titleVisibility: .visible) {
                Button(L10n.tr("New route"), role: .destructive) { remember(); cancelBuild(); library.draft = SavedRoute() }
            }
            .onChange(of: library.draft.kind) { _, kind in
                cancelBuild()
                if kind == .straight, library.draft.waypoints.isEmpty, !library.draft.path.isEmpty {
                    library.draft.waypoints = Array(library.draft.path.prefix(200))
                }
            }
            .onChange(of: session.travelMode) { _, _ in if library.draft.kind == .road { invalidatePath() } }
            .task {
                if let url = library.incomingGPX { library.incomingGPX = nil; importGPX(url) }
            }
            .onDisappear { cancelBuild(); library.flush() }
        }
    }
    private var waypointRows: some View {
        ForEach(Array(library.draft.waypoints.enumerated()), id: \.element.id) { index, point in
            Button { editingPoint = point } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.name.isEmpty ? L10n.format("Waypoint %d", index + 1) : point.name)
                    Text(CoordinateConverter.label(point.coordinate)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    if point.dwellSeconds > 0 { Text(L10n.format("Dwell %.0f seconds", point.dwellSeconds)).font(.caption) }
                }
            }
        }
        .onDelete { indexes in remember(); library.draft.waypoints.remove(atOffsets: indexes); invalidatePath() }
        .onMove { source, destination in remember(); library.draft.waypoints.move(fromOffsets: source, toOffset: destination); invalidatePath() }
    }
    private var playbackSection: some View {
        Section(L10n.tr("Playback")) {
            Picker(L10n.tr("Repeat mode"), selection: Binding(get: { library.draft.options.repeatMode }, set: { value in
                remember(); library.draft.options.repeatMode = value
                if library.draft.kind == .road { invalidatePath() }
            })) {
                ForEach(RouteRepeatMode.allCases) { Text($0.title).tag($0) }
            }
            if library.draft.options.repeatMode != .once {
                Stepper(L10n.format("Repetitions: %d", library.draft.options.repetitions), value: $library.draft.options.repetitions, in: 1...100)
            }
            Toggle(L10n.tr("Reverse direction"), isOn: $library.draft.options.reversed)
            if library.draft.kind == .gpx {
                Toggle(L10n.tr("Use recorded GPX timing"), isOn: $library.draft.options.useRecordedTiming)
            }
            if !library.draft.options.useRecordedTiming {
                LabeledContent(L10n.tr("Speed"), value: String(format: "%.1f m/s · %.1f km/h", library.draft.options.metersPerSecond, library.draft.options.metersPerSecond * 3.6))
                Slider(value: $library.draft.options.metersPerSecond, in: 0.1...60, step: 0.1)
                    .accessibilityLabel(L10n.tr("Speed"))
                Button(L10n.tr("Use selected travel speed")) { library.draft.options.metersPerSecond = session.travelMode.baseSpeed * session.speedMultiplier }
            }
            if library.draft.options.repeatMode == .loop {
                Text(library.draft.kind == .road ? L10n.tr("Road loops include a planned road segment back to the first waypoint. Rebuild after changing repeat mode.") : L10n.tr("Closed loops add a straight segment from the end back to the start. Recorded GPX timing uses the selected speed for this added segment."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func remember() { history.append(library.draft); history = Array(history.suffix(5)) }
    private func invalidatePath() { cancelBuild(); library.draft.path = []; library.draft.options.useRecordedTiming = false }
    private func cancelBuild() { requestID = UUID(); buildTask?.cancel(); buildTask = nil; isRouting = false }
    private func buildRoad() {
        let draft = library.draft, mode = session.travelMode
        guard draft.waypoints.count >= 2 else { error = L10n.tr("Set a route start and end."); return }
        cancelBuild(); isRouting = true
        let id = requestID
        buildTask = Task {
            do {
                let path = try await RouteBuilder.roadRoute(waypoints: draft.waypoints, mode: mode, closed: draft.options.repeatMode == .loop)
                try Task.checkCancellation()
                guard id == requestID, library.draft.waypoints == draft.waypoints else { return }
                remember(); library.draft.path = path; isRouting = false
            } catch {
                guard id == requestID else { return }
                isRouting = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    private func importGPX(_ url: URL) {
        guard !importing else { return }; importing = true
        Task {
            defer { importing = false }
            do {
                let segments = try await Task.detached(priority: .userInitiated) { try GPXCodec.parse(url) }.value
                imported = GPXSelection(segments: segments)
            } catch { self.error = error.localizedDescription }
        }
    }
    private func exportGPX() {
        let points = library.draft.playbackPoints
        guard !points.isEmpty else { error = L10n.tr("Nothing to export."); return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Locus-\(UUID().uuidString).gpx")
        do { try Data(GPXCodec.export(points: points, name: library.draft.name).utf8).write(to: url, options: .atomic); shared = SharedFile(url: url) }
        catch { self.error = error.localizedDescription }
    }
}

private struct WaypointEditor: View {
    @State var point: RoutePoint
    let onSave: (RoutePoint) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.tr("Name"), text: $point.name)
                Text(CoordinateConverter.label(point.coordinate)).textSelection(.enabled)
                Stepper(L10n.format("Dwell %.0f seconds", point.dwellSeconds), value: $point.dwellSeconds, in: 0...3600, step: 5)
            }
            .navigationTitle(L10n.tr("Edit waypoint"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("Save")) { onSave(point); dismiss() }.disabled(!point.isValid) }
            }
        }
    }
}
private struct GPXSelection: Identifiable {
    let id = UUID()
    let segments: [GPXSegment]
}
private struct GPXSelectionView: View {
    let segments: [GPXSegment]
    let onPick: (GPXSegment, CoordinateSystem) -> Void
    @State private var source = CoordinateSystem.wgs84
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Picker(L10n.tr("Input coordinate system"), selection: $source) {
                    ForEach(CoordinateSystem.allCases) { Text($0.rawValue).tag($0) }
                }
                Section {
                    ForEach(segments) { segment in
                        Button { onPick(segment, source); dismiss() } label: {
                            VStack(alignment: .leading) {
                                Text(segment.name.isEmpty ? L10n.format("Segment %d", segment.id + 1) : segment.name)
                                Text(L10n.format("%d points · %.1f km", segment.points.count, CoordinateMath.length(segment.coordinates) / 1000)).font(.caption)
                            }
                        }
                    }
                } footer: { Text(L10n.tr("Choose one segment. Separate tracks are never connected automatically.")) }
            }
            .navigationTitle(L10n.tr("Choose GPX segment"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("Cancel")) { dismiss() } } }
        }
    }
}
