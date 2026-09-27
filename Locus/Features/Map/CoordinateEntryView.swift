import SwiftUI
import CoreLocation

struct CoordinateEntryView: View {
    let initial: CLLocationCoordinate2D?
    let onSelect: (RoutePoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var name = ""
    @State private var system: CoordinateSystem = .wgs84
    @State private var longitudeFirst = false
    @State private var outputSystem: CoordinateSystem = .wgs84
    @State private var error: String?
    private var parsed: CLLocationCoordinate2D? {
        guard let value = try? CoordinateConverter.parse(text, longitudeFirst: longitudeFirst) else { return nil }
        return CoordinateConverter.convert(value, from: system, to: .wgs84)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("Enter coordinates")) {
                    TextField(L10n.tr("Name"), text: $name)
                    TextField(L10n.tr("Latitude, longitude"), text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker(L10n.tr("Input coordinate system"), selection: $system) {
                        ForEach(CoordinateSystem.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle(L10n.tr("Longitude first"), isOn: $longitudeFirst)
                    Button(L10n.tr("Paste coordinates")) { text = UIPasteboard.general.string ?? "" }
                    if let parsed { LabeledContent("WGS-84", value: CoordinateConverter.label(parsed)) }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Text(L10n.tr("MapKit, CoreLocation and standard GPX use WGS-84. Choose GCJ-02 or BD-09 only when the external source explicitly uses it. Conversion near coverage borders may be approximate."))
                        .font(.footnote)
                }
                if let value = parsed ?? initial {
                    Section(L10n.tr("Copy coordinates")) {
                        Picker(L10n.tr("Output coordinate system"), selection: $outputSystem) {
                            ForEach(CoordinateSystem.allCases) { Text($0.rawValue).tag($0) }
                        }
                        let output = CoordinateConverter.convert(value, from: .wgs84, to: outputSystem)
                        Text(CoordinateConverter.label(output)).font(.body.monospaced()).textSelection(.enabled)
                        Button(L10n.tr("Copy latitude, longitude")) { UIPasteboard.general.string = CoordinateConverter.label(output) }
                    }
                }
            }
            .navigationTitle(L10n.tr("Coordinates"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Use location")) {
                        do {
                            let input = try CoordinateConverter.parse(text, longitudeFirst: longitudeFirst)
                            let point = CoordinateConverter.convert(input, from: system, to: .wgs84)
                            guard CoordinateMath.isValid(point), name.count <= 200 else { throw RouteError.invalid }
                            onSelect(RoutePoint(point, name: name)); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .onAppear { if let initial { text = CoordinateConverter.label(initial) } }
        }
    }
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct FileShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
