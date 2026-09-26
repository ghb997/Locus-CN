import Foundation
import Darwin

enum TunnelConfig {
    /// LocalDevVPN / SideStore-style loopback tunnel endpoint.
    static let defaultIP = "10.7.0.1"
    static let defaultsKey = "locus.targetDeviceIP"

    static var targetIP: String {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return defaultIP }
        return stored
    }

    @discardableResult
    static func setTargetIP(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var address = in_addr()
        guard candidate.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else { return false }
        UserDefaults.standard.set(candidate, forKey: defaultsKey)
        return true
    }
}
