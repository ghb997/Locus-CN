import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var diagnostics: ConnectionDiagnostics
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    var body: some View {
        List {
            Section {
                ForEach(diagnostics.steps) { step in
                    HStack {
                        Image(systemName: icon(step.state))
                            .foregroundStyle(step.state == .failed ? .red : step.state == .passed ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(step.stage.title)
                            if !step.detail.isEmpty { Text(step.detail).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if step.state == .running { ProgressView() }
                    }
                }
            } footer: {
                Text(L10n.tr("Checks pairing, local TCP access, the developer tunnel and the location service. It does not send or clear coordinates. Signing validity and Developer Mode must be checked in iOS Settings."))
            }
            Section {
                if diagnostics.isRunning {
                    Button(L10n.tr("Cancel")) { diagnostics.cancel() }.disabled(diagnostics.cancellationRequested)
                    if diagnostics.cancellationRequested {
                        Text(L10n.tr("Cancellation requested. Waiting for the current native operation to finish safely.")).font(.footnote)
                    }
                } else {
                    Button(L10n.tr("Check connection")) { diagnostics.run(pairing: pairing) }.disabled(!session.canEditConnection)
                }
                if diagnostics.succeeded { Label(L10n.tr("Connection checks passed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                ShareLink(item: diagnostics.report()) { Label(L10n.tr("Share diagnostic report"), systemImage: "square.and.arrow.up") }
                    .disabled(diagnostics.isRunning || diagnostics.checkedAt == nil)
                Button(L10n.tr("Open LocalDevVPN")) { LocalDevVPN.openOrInstall() }
                Link(L10n.tr("Setup and troubleshooting"), destination: URL(string: "https://github.com/ghb997/Locus-CN/blob/main/SETUP.md")!)
            }
        }
        .navigationTitle(L10n.tr("Connection diagnostics"))
        .onDisappear { if diagnostics.isRunning { diagnostics.cancel() } }
    }
    private func icon(_ state: DiagnosticStep.State) -> String {
        switch state { case .waiting: return "circle"; case .running: return "arrow.triangle.2.circlepath"; case .passed: return "checkmark.circle.fill"; case .failed: return "exclamationmark.triangle.fill" }
    }
}
