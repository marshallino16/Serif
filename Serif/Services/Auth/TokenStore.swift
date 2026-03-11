import Foundation
import CryptoKit
import Security

/// Persists OAuth tokens in UserDefaults, encrypted with AES-256-GCM.
/// The symmetric key is stored in the macOS Keychain, tokens stay in UserDefaults.
final class TokenStore {
    static let shared = TokenStore()
    private init() {
        migrateKeyFromUserDefaultsIfNeeded()
    }

    private let defaults      = UserDefaults.standard
    private let keyPrefix     = "com.serif.token."
    private let accountsKey   = "com.serif.token.accounts"
    private let keychainService = "com.serif.token"
    private let keychainAccount = "encryption-key"
    private let legacyKeyUD    = "com.serif.token.key"

    // MARK: - Symmetric key (Keychain)

    private var symmetricKey: SymmetricKey {
        if let data = loadKeyFromKeychain() {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        saveKeyToKeychain(keyData)
        return key
    }

    private func loadKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      keychainService,
            kSecAttrAccount as String:      keychainAccount,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func saveKeyToKeychain(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      keychainService,
            kSecAttrAccount as String:      keychainAccount,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }
    }

    private func migrateKeyFromUserDefaultsIfNeeded() {
        guard let legacyData = defaults.data(forKey: legacyKeyUD) else { return }
        guard loadKeyFromKeychain() == nil else {
            defaults.removeObject(forKey: legacyKeyUD)
            return
        }
        saveKeyToKeychain(legacyData)
        defaults.removeObject(forKey: legacyKeyUD)
    }

    // MARK: - CRUD

    func save(_ token: AuthToken, for accountID: String) throws {
        let plaintext = try JSONEncoder().encode(token)
        let sealed    = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealed.combined else { throw TokenStoreError.encryptionFailed }
        defaults.set(combined, forKey: keyPrefix + accountID)

        var ids = allAccountIDs()
        if !ids.contains(accountID) {
            ids.append(accountID)
            defaults.set(ids, forKey: accountsKey)
        }
    }

    func retrieve(for accountID: String) throws -> AuthToken? {
        guard let combined = defaults.data(forKey: keyPrefix + accountID) else { return nil }
        let box       = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(box, using: symmetricKey)
        return try JSONDecoder().decode(AuthToken.self, from: plaintext)
    }

    func delete(for accountID: String) {
        defaults.removeObject(forKey: keyPrefix + accountID)
        var ids = allAccountIDs()
        ids.removeAll { $0 == accountID }
        defaults.set(ids, forKey: accountsKey)
    }

    func allAccountIDs() -> [String] {
        defaults.stringArray(forKey: accountsKey) ?? []
    }
}

enum TokenStoreError: Error, LocalizedError {
    case encryptionFailed

    var errorDescription: String? { "Token encryption failed" }
}
