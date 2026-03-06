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
    var historyId:         String?
    var accentColor:       String?
}

/// Persists the list of connected accounts to UserDefaults.
/// Tokens are stored separately in the Keychain via TokenStore.
final class AccountStore {
    static let shared = AccountStore()

    static let accentPalette = [
        "#FF6B6B", "#4ECDC4", "#45B7D1", "#F7DC6F",
        "#BB8FCE", "#F0932B", "#6C5CE7", "#A3CB38"
    ]

    private init() { migrateColors() }

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
        var acct = account
        if acct.accentColor == nil {
            let used = Set(accounts.compactMap(\.accentColor))
            acct.accentColor = Self.accentPalette.first { !used.contains($0) }
                ?? Self.accentPalette[accounts.count % Self.accentPalette.count]
        }
        var all = accounts
        all.removeAll { $0.id == acct.id }
        all.append(acct)
        accounts = all
    }

    func remove(id: String) {
        accounts = accounts.filter { $0.id != id }
        TokenStore.shared.delete(for: id)
        AttachmentDatabase.shared.deleteByAccountID(id)
        MailCacheStore.shared.deleteAccount(id)
        UnsubscribeService.shared.clearAccount(id)
        ContactStore.shared.deleteAccount(id)
        Task { @MainActor in SubscriptionsStore.shared.deleteAccount(id) }
        // Clean per-account UserDefaults
        UserDefaults.standard.removeObject(forKey: "signatureForNew.\(id)")
        UserDefaults.standard.removeObject(forKey: "signatureForReply.\(id)")
        UserDefaults.standard.removeObject(forKey: "attachmentExclusionRules.\(id)")
        // Purge avatar disk cache
        AvatarCache.shared.clearAll()
    }

    func update(_ account: GmailAccount) {
        var all = accounts
        if let idx = all.firstIndex(where: { $0.id == account.id }) {
            all[idx] = account
            accounts = all
        }
    }

    func setAsDefault(id: String) {
        var all = accounts
        guard let idx = all.firstIndex(where: { $0.id == id }), idx != 0 else { return }
        let account = all.remove(at: idx)
        all.insert(account, at: 0)
        accounts = all
    }

    func moveUp(id: String) {
        var all = accounts
        guard let idx = all.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        all.swapAt(idx, idx - 1)
        accounts = all
    }

    func moveDown(id: String) {
        var all = accounts
        guard let idx = all.firstIndex(where: { $0.id == id }), idx < all.count - 1 else { return }
        all.swapAt(idx, idx + 1)
        accounts = all
    }

    func setAccentColor(id: String, hex: String) {
        var all = accounts
        if let idx = all.firstIndex(where: { $0.id == id }) {
            all[idx].accentColor = hex
            accounts = all
        }
    }

    /// Assigns accent colors to any accounts that don't have one yet.
    private func migrateColors() {
        var all = accounts
        var changed = false
        var used = Set(all.compactMap(\.accentColor))
        for i in all.indices where all[i].accentColor == nil {
            let color = Self.accentPalette.first { !used.contains($0) }
                ?? Self.accentPalette[i % Self.accentPalette.count]
            all[i].accentColor = color
            used.insert(color)
            changed = true
        }
        if changed { accounts = all }
    }
}
