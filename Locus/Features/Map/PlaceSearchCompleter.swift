import MapKit
import Foundation

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    private var completer: MKLocalSearchCompleter?
    private var localSearch: MKLocalSearch?
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    var query = "" { didSet { updateQuery() } }

    func cancel() {
        requestID = UUID(); task?.cancel(); task = nil
        localSearch?.cancel(); localSearch = nil; completer?.cancel(); completer = nil
        isLoading = false
    }
    private func updateQuery() {
        cancel(); results = []; error = nil
        let fragment = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else { return }
        let id = requestID
        task = Task {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard id == requestID else { return }
            let newCompleter = MKLocalSearchCompleter()
            completer = newCompleter; newCompleter.delegate = self
            newCompleter.resultTypes = [.address, .pointOfInterest]
            isLoading = true; newCompleter.queryFragment = fragment
        }
    }
    func select(_ completion: MKLocalSearchCompletion, onResult: @escaping (MKMapItem) -> Void) {
        cancel(); error = nil; isLoading = true
        let id = requestID
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        localSearch = search
        task = Task {
            do {
                let response = try await search.start()
                try Task.checkCancellation()
                guard requestID == id else { return }
                isLoading = false
                guard let item = response.mapItems.first else { error = L10n.tr("No matching place was found. Try a more specific search."); return }
                onResult(item)
            } catch {
                guard requestID == id else { return }
                isLoading = false
                if !(error is CancellationError) { self.error = L10n.format("Search failed: %@", error.localizedDescription) }
            }
        }
    }
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in
            guard self.completer === completer, !self.query.isEmpty else { return }
            self.results = items; self.isLoading = false
            self.error = items.isEmpty ? L10n.tr("No matching place was found. Try a more specific search.") : nil
        }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.completer === completer else { return }
            self.results = []; self.isLoading = false
            self.error = L10n.format("Search failed: %@", error.localizedDescription)
        }
    }
}
