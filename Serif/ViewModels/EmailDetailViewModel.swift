import SwiftUI

/// Drives the email detail / thread view.
@MainActor
final class EmailDetailViewModel: ObservableObject {
    @Published var thread:          GmailThread?
    @Published var isLoading        = false
    @Published var error:           String?
    @Published var rawSource:       String?
    @Published var isLoadingRaw     = false

    let accountID: String

    init(accountID: String) {
        self.accountID = accountID
    }

    // MARK: - Load

    func loadThread(id: String) async {
        isLoading = true
        error     = nil
        defer { isLoading = false }

        // Load from disk cache first (instant + offline)
        if let cached = MailCacheStore.shared.loadThread(accountID: accountID, threadID: id) {
            thread = cached
        }

        // Refresh from API
        do {
            let fresh = try await GmailMessageService.shared.getThread(id: id, accountID: accountID)
            thread = fresh
            MailCacheStore.shared.saveThread(fresh, accountID: accountID)
            // Mark all unread messages in the thread as read
            for message in fresh.messages ?? [] where message.isUnread {
                try? await GmailMessageService.shared.markAsRead(id: message.id, accountID: accountID)
            }
        } catch {
            // Keep cached thread if API fails (offline mode)
            if thread == nil { self.error = error.localizedDescription }
        }
    }

    // MARK: - Attachments

    func downloadAttachment(messageID: String, part: GmailMessagePart) async throws -> Data {
        guard let attachmentID = part.body?.attachmentId else {
            throw GmailAPIError.decodingError(URLError(.badServerResponse))
        }
        return try await GmailMessageService.shared.getAttachment(
            messageID:    messageID,
            attachmentID: attachmentID,
            accountID:    accountID
        )
    }

    // MARK: - Label mutation (optimistic local update)

    func updateLabelIDs(_ labelIDs: [String]) {
        guard let msgs = thread?.messages, let lastID = msgs.last?.id else { return }
        var updated = msgs
        if let idx = updated.firstIndex(where: { $0.id == lastID }) {
            updated[idx].labelIds = labelIDs
        }
        thread = GmailThread(id: thread!.id, historyId: thread!.historyId, messages: updated)
    }

    /// Optimistically toggles the STARRED label on the latest message.
    func toggleStar() {
        guard var labelIDs = latestMessage?.labelIds else { return }
        if labelIDs.contains("STARRED") {
            labelIDs.removeAll { $0 == "STARRED" }
        } else {
            labelIDs.append("STARRED")
        }
        updateLabelIDs(labelIDs)
    }

    // MARK: - Raw source

    func fetchRawSource() async {
        guard let msgID = latestMessage?.id else { return }
        guard rawSource == nil else { return }
        isLoadingRaw = true
        defer { isLoadingRaw = false }
        do {
            let raw = try await GmailMessageService.shared.getRawMessage(id: msgID, accountID: accountID)
            rawSource = raw.rawSource
        } catch {
            rawSource = nil
        }
    }

    // MARK: - Convenience

    var messages: [GmailMessage] { thread?.messages ?? [] }
    var latestMessage: GmailMessage? { messages.last }
}
