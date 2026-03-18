import SwiftUI

/// Handles incremental delta sync via the Gmail History API.
@MainActor
final class HistorySyncService {

    private let api: MessageFetching

    init(api: MessageFetching = GmailMessageService.shared) {
        self.api = api
    }

    /// Result of a successful history sync operation.
    struct SyncResult {
        var deletedIDs: Set<String> = []
        var newMessages: [GmailMessage] = []
        var refreshedMessages: [GmailMessage] = []
        var latestHistoryId: String?
        var succeeded: Bool = false
        var error: String?
    }

    /// Attempts incremental sync using Gmail History API.
    /// - Parameters:
    ///   - accountID: The account to sync.
    ///   - labelId: Optional label to filter history by.
    ///   - existingMessageIDs: IDs of messages currently displayed, used to avoid
    ///     re-fetching messages we already have and to scope label-change refreshes.
    /// Returns a `SyncResult` with the changes to apply.
    func syncViaHistory(
        accountID: String,
        labelId: String? = nil,
        existingMessageIDs: Set<String>
    ) async -> SyncResult {
        guard let account = AccountStore.shared.accounts.first(where: { $0.id == accountID }),
              let startHistoryId = account.historyId else {
            return SyncResult(succeeded: false)
        }

        var result = SyncResult()

        do {
            var allAdded: [String] = []
            var allDeleted: Set<String> = []
            var labelChanges: Set<String> = []
            var latestHistoryId = startHistoryId
            var pageToken: String? = nil

            repeat {
                let response = try await api.listHistory(
                    accountID: accountID,
                    startHistoryId: startHistoryId,
                    labelId: labelId,
                    pageToken: pageToken,
                    maxResults: 500
                )

                latestHistoryId = response.historyId
                pageToken = response.nextPageToken

                for record in response.history ?? [] {
                    for added in record.messagesAdded ?? [] {
                        allAdded.append(added.message.id)
                    }
                    for deleted in record.messagesDeleted ?? [] {
                        allDeleted.insert(deleted.message.id)
                    }
                    for labelAdd in record.labelsAdded ?? [] {
                        labelChanges.insert(labelAdd.message.id)
                    }
                    for labelRemove in record.labelsRemoved ?? [] {
                        labelChanges.insert(labelRemove.message.id)
                    }
                }
            } while pageToken != nil

            result.deletedIDs = allDeleted
            result.latestHistoryId = latestHistoryId

            // Fetch new messages (not already displayed and not deleted)
            let newIDs = allAdded.filter { !existingMessageIDs.contains($0) && !allDeleted.contains($0) }

            if !newIDs.isEmpty {
                let fetched = try await api.getMessages(
                    ids: newIDs, accountID: accountID, format: "metadata"
                )
                // Only include messages that still belong to the current folder.
                // A message may appear in messagesAdded but then get moved/trashed
                // before we sync, so its labels no longer match.
                result.newMessages = fetched
                    .filter { msg in
                        guard let labelId else { return true }
                        return msg.labelIds?.contains(labelId) == true
                    }
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            }

            // Re-fetch messages with label changes to update their labelIds
            // Only refresh messages that are currently displayed and weren't just added/deleted
            let toRefetch = labelChanges.subtracting(allDeleted).subtracting(Set(newIDs)).filter { existingMessageIDs.contains($0) }
            if !toRefetch.isEmpty {
                let refreshed = try await api.getMessages(
                    ids: Array(toRefetch), accountID: accountID, format: "metadata"
                )
                result.refreshedMessages = refreshed
            }

            result.succeeded = true
            return result

        } catch let error as GmailAPIError {
            if case .httpError(let code, _) = error, code == 404 {
                // historyId expired -- fall back to full refresh
                updateStoredHistoryId(nil, accountID: accountID)
                return SyncResult(succeeded: false)
            }
            result.succeeded = true // Don't trigger full refresh for other API errors
            result.error = error.localizedDescription
            return result
        } catch {
            result.succeeded = true
            result.error = error.localizedDescription
            return result
        }
    }

    /// Updates the persisted historyId for the given account.
    func updateStoredHistoryId(_ historyId: String?, accountID: String) {
        guard var account = AccountStore.shared.accounts.first(where: { $0.id == accountID }) else { return }
        account.historyId = historyId
        AccountStore.shared.update(account)
    }
}
