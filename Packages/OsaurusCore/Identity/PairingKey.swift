//
//  PairingKey.swift
//  osaurus
//
//  Deterministic pairing identity derived from the Master Key.
//  Scoped to peer-pairing operations — distinct from agent keys and the master address.
//

import CryptoKit
import Foundation

struct PairingKey {

    static func derive(masterKey: Data) -> Data {
        let domain = Data("osaurus-pairing-v1".utf8)
        let hmac = HMAC<SHA512>.authenticationCode(for: domain, using: SymmetricKey(data: masterKey))
        return Data(hmac.prefix(32))
    }

    static func deriveAddress(masterKey: Data) throws -> OsaurusID {
        try deriveOsaurusId(from: derive(masterKey: masterKey))
    }

    static func signEIP191(_ message: String, masterKey: Data) throws -> Data {
        var key = derive(masterKey: masterKey)
        defer { key.resetBytes(in: key.startIndex..<key.endIndex) }
        return try signEIP191Message(message, privateKey: key)
    }
}
