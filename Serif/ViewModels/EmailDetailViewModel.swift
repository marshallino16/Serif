import SwiftUI

/// Drives the email detail / thread view.
@MainActor
final class EmailDetailViewModel: ObservableObject {
    @Published var thread:          GmailThread?
    @Published var isLoading        = false
    @Published var error:           String?
    @Published var rawSource:       String?
    @Published var isLoadingRaw     = false
    @Published var trackerResult:   TrackerResult?
    @Published var allowTrackers    = false
    @Published var resolvedHTML:    String?

    /// HTML to render: sanitized (trackers stripped) or original when user allows.
    var displayHTML: String? {
        guard let result = trackerResult else { return nil }
        return allowTrackers ? result.originalHTML : result.sanitizedHTML
    }

    var blockedTrackerCount: Int { trackerResult?.trackerCount ?? 0 }
    var hasBlockedTrackers: Bool { !allowTrackers && (trackerResult?.hasTrackers ?? false) }

    let accountID: String
    var attachmentIndexer: AttachmentIndexer?

    init(accountID: String) {
        self.accountID = accountID
    }

    // MARK: - Load

    func loadThread(id: String) async {
        isLoading = true
        error     = nil
        allowTrackers = false
        defer { isLoading = false }

        resolvedHTML = nil

        // Load from disk cache first (instant + offline)
        if let cached = MailCacheStore.shared.loadThread(accountID: accountID, threadID: id) {
            thread = cached
            analyzeTrackers()
        }

        // Refresh from API
        do {
            let fresh = try await GmailMessageService.shared.getThread(id: id, accountID: accountID)
            thread = fresh
            analyzeTrackers()
            if let latest = fresh.messages?.last {
                await resolveInlineImages(for: latest)
            }
            MailCacheStore.shared.saveThread(fresh, accountID: accountID)
            // Passive attachment registration from full-format messages
            if let indexer = attachmentIndexer, let messages = fresh.messages {
                let withAttachments = messages.filter { !$0.attachmentParts.isEmpty }
                if !withAttachments.isEmpty {
                    Task { await indexer.registerFromFullMessages(messages: withAttachments) }
                }
            }
            // Mark all unread messages in the thread as read
            for message in fresh.messages ?? [] where message.isUnread {
                try? await GmailMessageService.shared.markAsRead(id: message.id, accountID: accountID)
            }
        } catch {
            // Keep cached thread if API fails (offline mode)
            if thread == nil { self.error = error.localizedDescription }
        }
    }

    func allowBlockedContent() {
        allowTrackers = true
    }

    // MARK: - Tracker analysis

    private func analyzeTrackers() {
        guard let html = latestMessage?.htmlBody, !html.isEmpty else {
            trackerResult = nil
            return
        }
        trackerResult = TrackerBlockerService.shared.sanitize(html: html)
    }

    // MARK: - Inline Image Resolution

    /// Downloads inline CID images and replaces cid: references with data: URIs in the HTML.
    private func resolveInlineImages(for message: GmailMessage) async {
        let inlineParts = message.inlineParts
        guard !inlineParts.isEmpty else { resolvedHTML = nil; return }

        let baseHTML = displayHTML ?? message.htmlBody ?? ""
        guard !baseHTML.isEmpty else { resolvedHTML = nil; return }

        var html = baseHTML
        await withTaskGroup(of: (String, String, Data?).self) { group in
            for part in inlineParts {
                guard let cid = part.contentID,
                      let attachmentID = part.body?.attachmentId,
                      let mime = part.mimeType else { continue }
                group.addTask { [accountID] in
                    let data = try? await GmailMessageService.shared.getAttachment(
                        messageID: message.id,
                        attachmentID: attachmentID,
                        accountID: accountID
                    )
                    return (cid, mime, data)
                }
            }
            for await (cid, mime, data) in group {
                guard let data = data else { continue }
                let dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
                html = html.replacingOccurrences(of: "cid:\(cid)", with: dataURI)
            }
        }
        resolvedHTML = html
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
