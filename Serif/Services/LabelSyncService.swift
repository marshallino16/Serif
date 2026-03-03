import Foundation

/// Handles label loading, sendAs aliases, and category unread counts.
@MainActor
final class LabelSyncService {

    private let cache: CacheStoring

    init(cache: CacheStoring = MailCacheStore.shared) {
        self.cache = cache
    }

    /// Loads labels from disk cache first, then refreshes from the API.
    /// Returns the labels and an optional error message.
    func loadLabels(
        accountID: String,
        currentLabels: [GmailLabel]
    ) async -> (labels: [GmailLabel], error: String?) {
        var labels = currentLabels
        // Load from disk cache first
        let cached = cache.loadLabels(accountID: accountID)
        if !cached.isEmpty && labels.isEmpty {
            labels = cached
        }
        // Refresh from API
        do {
            let fresh = try await GmailLabelService.shared.listLabels(accountID: accountID)
            labels = fresh
            cache.saveLabels(fresh, accountID: accountID)
            return (labels, nil)
        } catch {
            if labels.isEmpty {
                return (labels, error.localizedDescription)
            }
            return (labels, nil)
        }
    }

    /// Loads the sendAs aliases for the given account.
    func loadSendAs(accountID: String) async -> (aliases: [GmailSendAs], error: String?) {
        do {
            let aliases = try await GmailProfileService.shared.listSendAs(accountID: accountID)
            return (aliases, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    /// Loads unread counts per inbox category via parallel label fetches.
    func loadCategoryUnreadCounts(accountID: String) async -> [InboxCategory: Int] {
        guard !accountID.isEmpty else { return [:] }
        let aid = accountID
        var counts: [InboxCategory: Int] = [:]
        await withTaskGroup(of: (InboxCategory, Int)?.self) { group in
            for category in InboxCategory.allCases {
                let labelID = (category == .all) ? "INBOX" : category.rawValue
                group.addTask {
                    guard let label = try? await GmailLabelService.shared.getLabel(id: labelID, accountID: aid),
                          let unread = label.messagesUnread, unread > 0 else { return nil }
                    return (category, unread)
                }
            }
            for await result in group {
                if let (category, count) = result { counts[category] = count }
            }
        }
        return counts
    }
}
