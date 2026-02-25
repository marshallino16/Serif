import Foundation

/// Represents a connected Gmail account.
struct GmailAccount: Identifiable, Codable, Equatable {
    var id: String { email }
    let email:             String
    let displayName:       String
    let profilePictureURL: URL?
    var messagesTotal:     Int
    var threadsTotal:      Int
    var signature:         String?
    var unreadCount:       Int
}

/// Persists the list of connected accounts to UserDefaults.
/// Tokens are stored separately in the Keychain via TokenStore.
final class AccountStore {
    static let shared = AccountStore()
    private init() {}

    private let key = "com.serif.accounts"

    var accounts: [GmailAccount] {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: key),
                let decoded = try? JSONDecoder().decode([GmailAccount].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(_ account: GmailAccount) {
        var all = accounts
        all.removeAll { $0.id == account.id }
        all.append(account)
        accounts = all
    }

    func remove(id: String) {
        accounts = accounts.filter { $0.id != id }
        TokenStore.shared.delete(for: id)
    }

    func update(_ account: GmailAccount) {
        var all = accounts
        if let idx = all.firstIndex(where: { $0.id == account.id }) {
            all[idx] = account
            accounts = all
        }
    }
}
