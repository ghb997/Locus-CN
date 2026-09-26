import Foundation
import CryptoKit

enum PairingImportError: LocalizedError {
    case emptyClipboard
    case invalidContents
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .emptyClipboard: return L10n.tr("Clipboard is empty. Copy your RPPairing plist text (or the file), then try Paste again.")
        case .invalidContents: return L10n.tr("Invalid RPPairing file. It must contain matching Ed25519 keys and an identifier. Lockdown / SideStore pairing files are not supported.")
        case .tooLarge: return L10n.tr("The pairing file exceeds the 1 MB limit.")
        }
    }
}

enum PairingValidator {
    static let maximumBytes = 1_048_576

    static func validate(_ data: Data) throws {
        guard data.count <= maximumBytes else { throw PairingImportError.tooLarge }
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = object as? [String: Any],
              let identifier = dict["identifier"] as? String,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let privateKey = dict["private_key"] as? Data,
              let publicKey = dict["public_key"] as? Data,
              privateKey.count == 32, publicKey.count == 32,
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey),
              key.publicKey.rawRepresentation == publicKey else {
            throw PairingImportError.invalidContents
        }
        if let irk = dict["alt_irk"], (irk as? Data)?.count != 16 {
            throw PairingImportError.invalidContents
        }
    }
}
