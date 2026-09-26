import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? L10n.tr("RPPairing file installed") : L10n.tr("No pairing file"))
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label(L10n.tr("Pair on this iPhone"), systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button(L10n.tr("Import RPPairing file…")) { showImporter = true }
                    Button(L10n.tr("Paste RPPairing from clipboard")) {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button(L10n.tr("Remove pairing file"), role: .destructive) {
                            do { try pairing.removePairing() }
                            catch { session.lastError = error.localizedDescription }
                        }
                    }
                } header: {
                    Text(L10n.tr("Developer pairing"))
                } footer: {
                    Text(supportsOnDevicePairing
                         ? L10n.tr("On iOS 27, use Pair on this iPhone — no computer. Locus advertises a pairable host; confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On older iOS, import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). LiveContainer: enable Fix File Picker on Locus, or use Paste / Share → LiveContainer → Locus.")
                         : L10n.tr("Import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). If the file picker fails (common in LiveContainer), enable Fix File Picker on the app, share the file into LiveContainer → Locus, or copy the plist and use Paste."))
                }

                .disabled(session.canStop)

                Section {
                    TextField(L10n.tr("Device tunnel IP"), text: $tunnelIP)
                        .disabled(session.canStop)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            saveTunnelIP()
                        }
                    LabeledContent(L10n.tr("Status")) {
                        Text(LocalDevVPN.isConnected ? L10n.tr("Tunnel interface detected") : L10n.tr("Tunnel interface not detected"))
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button(L10n.tr("Save tunnel IP")) {
                        saveTunnelIP()
                    }
                    .disabled(session.canStop)
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? L10n.tr("Open LocalDevVPN") : L10n.tr("Get LocalDevVPN (App Store)"),
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text(L10n.tr("Tunnel"))
                } footer: {
                    Text(L10n.tr("Connect LocalDevVPN before teleporting. Default tunnel IP is 10.7.0.1. Start a spoof on Wi‑Fi first; it can keep working on cellular afterward."))
                }

                Section(L10n.tr("Location status")) {
                    LabeledContent(L10n.tr("Last successful command")) {
                        Text(session.lastCommandAt?.formatted(date: .omitted, time: .standard) ?? "—")
                    }
                    Text(L10n.tr("A successful command does not verify other apps or a real GPS fix. After Stop, wait for a fresh system location."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.tr("Restore system location")) { session.stop(pairing: pairing) }
                        .disabled(session.isStopping || !pairing.hasPairingFile)
                }

                Section(L10n.tr("Privacy")) {
                    Text(L10n.tr("Favorites and pairing files stay on this device. Map search and routes use Apple Maps online services. No analytics or Locus account."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.tr("About")) {
                    LabeledContent(L10n.tr("Version"), value: appVersion)
                    LabeledContent(L10n.tr("Maintainer"), value: "ghb997")
                    Link(L10n.tr("Project source"), destination: URL(string: "https://github.com/ghb997/Locus-CN")!)
                    Link(L10n.tr("Original Locus project"), destination: URL(string: "https://github.com/ChrisMack32/Locus")!)
                    LabeledContent(L10n.tr("Engine"), value: L10n.tr("idevice DVT location simulation"))
                    Text(L10n.tr("Locus is free and open source (MIT). Location injection uses the MIT-licensed idevice FFI."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text(L10n.tr("locus, n. — a place. From the Latin for where you are."))
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle(L10n.tr("Settings"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Done")) {
                        if session.canStop || saveTunnelIP() { dismiss() }
                    }
                }
            }
            .alert("Locus", isPresented: Binding(
                get: { session.lastError != nil },
                set: { if !$0 { session.lastError = nil } }
            )) {
                Button(L10n.tr("OK"), role: .cancel) { session.lastError = nil }
            } message: {
                Text(session.lastError ?? "")
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }
    @discardableResult
    private func saveTunnelIP() -> Bool {
        guard !session.canStop else { return true }
        guard TunnelConfig.setTargetIP(tunnelIP) else {
            session.lastError = LocationEngineError.invalidIP.localizedDescription
            return false
        }
        tunnelIP = TunnelConfig.targetIP
        return true
    }
}

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("Favorites")) {
                    if session.favorites.isEmpty {
                        Text(L10n.tr("Star a pin from the map to save it."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.favorites) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeFavorite(place)
                                } label: {
                                    Label(L10n.tr("Delete"), systemImage: "trash.fill")
                                }
                                Button {
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
                                    Label(L10n.tr("Rename"), systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                    }
                }

                Section(L10n.tr("Recents")) {
                    if session.recents.isEmpty {
                        Text(L10n.tr("Teleports show up here."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label(L10n.tr("Delete"), systemImage: "trash.fill")
                                }
                            }
                    }
                }
            }
            .navigationTitle(L10n.tr("Places"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Done")) { dismiss() }
                }
            }
            .alert(L10n.tr("Rename Favorite"), isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField(L10n.tr("Name"), text: $renameText)
                Button(L10n.tr("Cancel"), role: .cancel) {
                    placeToRename = nil
                }
                Button(L10n.tr("Save")) {
                    if let place = placeToRename {
                        session.renameFavorite(place, to: renameText)
                    }
                    placeToRename = nil
                }
            } message: {
                Text(L10n.tr("Choose a name you’ll recognize later."))
            }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            session.teleport(to: place.coordinate, pairing: pairing)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
