import Foundation
import UniformTypeIdentifiers
import UIKit

@MainActor
final class PairingStore: ObservableObject {
    @Published private(set) var hasPairingFile = false
    @Published var lastError: String?

    static let fileName = "rp_pairing_file.plist"
    static let supportedTypes: [UTType] = {
        var types: [UTType] = [
            .item,          // anything — sideloaded plists often lack a proper UTI
            .data,
            .propertyList,
            .xml,
        ]
        for ext in ["plist", "mobiledevicepairing", "mobiledevicepair"] {
            if let t = UTType(filenameExtension: ext) {
                types.append(t)
            }
        }
        if let custom = UTType("io.github.ghb997.locus.rppairing") {
            types.append(custom)
        }
        return types
    }()

    private var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
    }

    var pairingURL: URL {
        directoryURL.appendingPathComponent(Self.fileName)
    }

    var pairingPath: String { pairingURL.path }

    init() {
        refresh()
    }

    func refresh() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        hasPairingFile = false
        if let size = try? pairingURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= PairingValidator.maximumBytes,
           let data = try? Data(contentsOf: pairingURL),
           (try? PairingValidator.validate(data)) != nil {
            hasPairingFile = true
        }
    }

    func importPairing(from sourceURL: URL) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        if let size = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > PairingValidator.maximumBytes { throw PairingImportError.tooLarge }
        let data = try Data(contentsOf: sourceURL)
        try installPairingData(data)
    }

    /// LiveContainer / broken pickers: copy the plist text (or file) then paste here.
    func importPairingFromClipboard() throws {
        let board = UIPasteboard.general

        if let url = board.url ?? board.urls?.first {
            if url.isFileURL {
                try importPairing(from: url)
                return
            }
        }

        let candidates: [Data?] = [
            board.data(forPasteboardType: "com.apple.property-list"),
            board.data(forPasteboardType: UTType.propertyList.identifier),
            board.data(forPasteboardType: UTType.xml.identifier),
            board.data(forPasteboardType: UTType.data.identifier),
            board.string?.data(using: .utf8),
        ]

        guard let data = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw PairingImportError.emptyClipboard
        }
        try installPairingData(data)
    }

    func removePairing() throws {
        if FileManager.default.fileExists(atPath: pairingURL.path) {
            try FileManager.default.removeItem(at: pairingURL)
        }
        hasPairingFile = false
    }

    func installPairingData(_ data: Data) throws {
        try PairingValidator.validate(data)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        // Atomic replacement preserves the last good file on validation/write failure.
        try data.write(to: pairingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pairingURL.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = pairingURL
        try? protectedURL.setResourceValues(values)
        hasPairingFile = true
        lastError = nil
    }

}
