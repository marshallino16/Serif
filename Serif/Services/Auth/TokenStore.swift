import Foundation
import CryptoKit

/// Persists OAuth tokens in UserDefaults, encrypted with AES-256-GCM.
/// A random symmetric key is generated on first launch and stored in UserDefaults.
/// This avoids macOS Keychain access prompts entirely.
final class TokenStore {
    static let shared = TokenStore()
    private init() {}

    private let defaults      = UserDefaults.standard
    private let keyPrefix     = "com.serif.token."
    private let accountsKey   = "com.serif.token.accounts"
    private let symmetricKeyUD = "com.serif.token.key"

    // MARK: - Symmetric key (generated once, persisted in UserDefaults)

    private var symmetricKey: SymmetricKey {
        if let data = defaults.data(forKey: symmetricKeyUD) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        defaults.set(key.withUnsafeBytes { Data($0) }, forKey: symmetricKeyUD)
        return key
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
