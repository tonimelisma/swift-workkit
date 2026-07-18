//
//  Keychain.swift
//  Work Agent
//
//  Credential storage. The only place API keys are allowed to live.
//

import Foundation
import Security

// REQ: FR-052 — provider credentials live in the Keychain and nowhere else. Nothing in
// this file logs a secret, and no caller should hold one longer than a request needs.

nonisolated enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case dataCorrupted

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Keychain error: \(message)"
        case .dataCorrupted:
            return "The stored credential could not be read."
        }
    }
}

/// Generic-password storage scoped to this app.
nonisolated enum Keychain {
    /// Distinct from the bundle id so a future non-credential Keychain use can't collide.
    private static let service = "net.melisma.Work-Agent.providers"

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Store or replace the secret for `account`.
    static func set(_ secret: String, account: String) throws {
        guard let data = secret.data(using: .utf8) else { throw KeychainError.dataCorrupted }

        // Delete-then-add rather than SecItemUpdate: fewer branches, and the update path
        // is only reachable when an item already exists, which we'd have to check anyway.
        SecItemDelete(query(account: account) as CFDictionary)

        var attributes = query(account: account)
        attributes[kSecValueData as String] = data
        // The agent needs keys after an unattended wake to run background work later;
        // ThisDeviceOnly keeps them off iCloud Keychain and off any other Mac.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// The secret for `account`, or nil if there isn't one.
    static func get(account: String) throws -> String? {
        var attributes = query(account: account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataCorrupted
            }
            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Remove the secret for `account`. Succeeds if there was nothing to remove.
    // REQ: FR-057 — removing a provider deletes its credential.
    static func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func exists(account: String) -> Bool {
        (try? get(account: account)) .flatMap { $0 } != nil
    }
}
