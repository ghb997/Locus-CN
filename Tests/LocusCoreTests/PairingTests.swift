import CryptoKit
import Foundation
import XCTest
@testable import LocusCore

final class PairingTests: XCTestCase {
    private func record() -> [String: Any] {
        let key = Curve25519.Signing.PrivateKey()
        return ["identifier": UUID().uuidString, "private_key": key.rawRepresentation,
                "public_key": key.publicKey.rawRepresentation, "alt_irk": Data(repeating: 1, count: 16)]
    }

    private func data(_ record: [String: Any], _ format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: record, format: format, options: 0)
    }

    func testValidXMLAndBinaryRecords() throws {
        try PairingValidator.validate(data(record()))
        try PairingValidator.validate(data(record(), .binary))
        var withoutIRK = record()
        withoutIRK.removeValue(forKey: "alt_irk")
        try PairingValidator.validate(data(withoutIRK))
    }

    func testRejectsLockdownAndUnrelatedPlists() throws {
        XCTAssertThrowsError(try PairingValidator.validate(data(["HostID": "example", "SystemBUID": "example"])))
        XCTAssertThrowsError(try PairingValidator.validate(Data("<?xml broken".utf8)))
    }

    func testRejectsMismatchedKeysMissingIdentifierAndMalformedIRK() throws {
        var candidate = record()
        candidate["public_key"] = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        XCTAssertThrowsError(try PairingValidator.validate(data(candidate)))
        candidate = record()
        candidate["identifier"] = "  "
        XCTAssertThrowsError(try PairingValidator.validate(data(candidate)))
        candidate = record()
        candidate["alt_irk"] = Data(repeating: 0, count: 15)
        XCTAssertThrowsError(try PairingValidator.validate(data(candidate)))
    }

    func testRejectsOversizePairingFiles() {
        XCTAssertThrowsError(try PairingValidator.validate(Data(repeating: 0, count: PairingValidator.maximumBytes + 1)))
    }
}
