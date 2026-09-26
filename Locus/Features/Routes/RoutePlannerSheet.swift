import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @Binding var start: CLLocationCoordinate2D?
    @Binding var end: CLLocationCoordinate2D?
    @Binding var isRouting: Bool
    var onBuild: () -> Void
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("Road route")) {
                    Button(L10n.tr("Use current pin / spoof as start")) {
                        start = session.simulated ?? session.pin
                    }
                    Button(L10n.tr("Use current pin as end")) {
                        end = session.pin
                    }
                    LabeledContent(L10n.tr("Start")) {
                        Text(coordText(start)).font(.caption.monospaced())
                    }
                    LabeledContent(L10n.tr("End")) {
                        Text(coordText(end)).font(.caption.monospaced())
                    }
                    Button {
                        onBuild()
                    } label: {
                        if isRouting {
                            ProgressView()
                        } else {
                            Label(L10n.tr("Build walk/drive route on roads"), systemImage: "road.lanes")
                        }
                    }
                    .disabled(isRouting)
                }

                Section(L10n.tr("Play / draw / GPX")) {
                    HStack {
                        Text(L10n.tr("Speed multiplier"))
                        Slider(value: $session.speedMultiplier, in: 0.25...4, step: 0.25)
                            .accessibilityLabel(L10n.tr("Speed multiplier"))
                        Text(String(format: "%.2f×", session.speedMultiplier)).monospacedDigit()
                    }
                    Button {
                        onUseDrawn()
                    } label: {
                        Label(L10n.tr("Use drawn path from map"), systemImage: "pencil.tip")
                    }
                    Button(action: onPlay) {
                        Label(L10n.tr("Follow route"), systemImage: "play.fill")
                    }
                    Button(action: onImportGPX) {
                        Label(L10n.tr("Import GPX"), systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label(L10n.tr("Export GPX"), systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Text(L10n.tr("Walking/running use walking directions. Cycling/driving use driving directions; cycling is a speed preset, not a bicycle route. The destination stays active until Stop is pressed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.tr("Routes"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Done")) { dismiss() }
                }
            }
        }
    }

    private func coordText(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "—" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}
