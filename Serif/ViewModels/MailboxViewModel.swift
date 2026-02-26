import SwiftUI

/// Drives the email list for a given account and folder.
@MainActor
final class MailboxViewModel: ObservableObject {
    @Published var messages:      [GmailMessage] = []
    @Published var isLoading      = false
    @Published var error:         String?
    @Published var nextPageToken: String?
    @Published var labels:                [GmailLabel] = []
    @Published var readIDs:               Set<String> = []
    @Published var categoryUnreadCounts:  [InboxCategory: Int] = [:]

    var accountID: String
    private var currentLabelIDs: [String] = ["INBOX"]
    private var currentQuery:    String?
    /// In-memory cache of fetched messages (metadata format) keyed by message ID.
    private var messageCache: [String: GmailMessage] = [:]

    init(accountID: String) {
        self.accountID = accountID
    }

    // MARK: - GmailMessage → Email (computed)

    var emails: [Email] {
        messages.map { makeEmail(from: $0) }
    }

    // MARK: - Load

    func loadFolder(labelIDs: [String], query: String? = nil) async {
        let isFolderChange = labelIDs != currentLabelIDs || query != currentQuery
        currentLabelIDs = labelIDs
        currentQuery    = query
        await fetchMessages(reset: true, clearFirst: isFolderChange)
    }

    func search(query: String) async {
        let newQuery = query.isEmpty ? nil : query
        let isNewQuery = newQuery != currentQuery
        currentQuery = newQuery
        await fetchMessages(reset: true, clearFirst: isNewQuery)
    }

    func loadMore() async {
        guard nextPageToken != nil else { return }
        await fetchMessages(reset: false)
    }

    func loadLabels() async {
        do { labels = try await GmailLabelService.shared.listLabels(accountID: accountID) }
        catch { self.error = error.localizedDescription }
    }

    func loadCategoryUnreadCounts() async {
        guard !accountID.isEmpty else { return }
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
        categoryUnreadCounts = counts
    }

    func switchAccount(_ id: String) async {
        accountID     = id
        messages      = []
        nextPageToken = nil
        readIDs       = []
        error         = nil
        messageCache  = [:]
    }

    // MARK: - Mutations

    func markAsRead(_ message: GmailMessage) async {
        guard message.isUnread && !readIDs.contains(message.id) else { return }
        readIDs.insert(message.id)
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx].labelIds?.removeAll { $0 == "UNREAD" }
            messageCache[message.id] = messages[idx]
        }
        try? await GmailMessageService.shared.markAsRead(id: message.id, accountID: accountID)
    }

    func markAsUnread(_ messageID: String) async {
        if let idx = messages.firstIndex(where: { $0.id == messageID }) {
            if messages[idx].labelIds?.contains("UNREAD") == false {
                messages[idx].labelIds?.append("UNREAD")
            }
            messageCache[messageID] = messages[idx]
        }
        readIDs.remove(messageID)
        do {
            try await GmailMessageService.shared.markAsUnread(id: messageID, accountID: accountID)
        } catch { self.error = error.localizedDescription }
    }

    func toggleStar(_ messageID: String, isStarred: Bool) async {
        if let idx = messages.firstIndex(where: { $0.id == messageID }) {
            if isStarred {
                messages[idx].labelIds?.removeAll { $0 == "STARRED" }
            } else {
                messages[idx].labelIds?.append("STARRED")
            }
            messageCache[messageID] = messages[idx]
        }
        do {
            try await GmailMessageService.shared.setStarred(!isStarred, id: messageID, accountID: accountID)
        } catch {
            // Revert on failure
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                if isStarred {
                    messages[idx].labelIds?.append("STARRED")
                } else {
                    messages[idx].labelIds?.removeAll { $0 == "STARRED" }
                }
                messageCache[messageID] = messages[idx]
            }
            self.error = error.localizedDescription
        }
    }

    func trash(_ messageID: String) async {
        do {
            try await GmailMessageService.shared.trashMessage(id: messageID, accountID: accountID)
            messages.removeAll { $0.id == messageID }   // no-op if already removed optimistically
            messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    func archive(_ messageID: String) async {
        do {
            try await GmailMessageService.shared.archiveMessage(id: messageID, accountID: accountID)
            messages.removeAll { $0.id == messageID }   // no-op if already removed optimistically
            messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Removes a message from the in-memory list immediately (optimistic UI).
    /// Returns the removed message so it can be put back if the action is undone.
    @discardableResult
    func removeOptimistically(_ messageID: String) -> GmailMessage? {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return nil }
        let msg = messages[idx]
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            messages.remove(at: idx)
        }
        return msg
    }

    /// Re-inserts a previously removed message at its original date position (undo path).
    func restoreOptimistically(_ message: GmailMessage) {
        let date = message.date ?? .distantPast
        let insertIdx = messages.firstIndex { ($0.date ?? .distantPast) < date } ?? messages.endIndex
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            messages.insert(message, at: insertIdx)
        }
    }

    func spam(_ messageID: String) async {
        do {
            try await GmailMessageService.shared.spamMessage(id: messageID, accountID: accountID)
            messages.removeAll { $0.id == messageID }
            messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    func addLabel(_ labelID: String, to messageID: String) async {
        do {
            let updated = try await GmailMessageService.shared.modifyLabels(
                id: messageID, add: [labelID], remove: [], accountID: accountID
            )
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                messages[idx].labelIds = updated.labelIds
                messageCache[messageID] = messages[idx]
            }
        } catch { self.error = error.localizedDescription }
    }

    func removeLabel(_ labelID: String, from messageID: String) async {
        do {
            let updated = try await GmailMessageService.shared.modifyLabels(
                id: messageID, add: [], remove: [labelID], accountID: accountID
            )
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                messages[idx].labelIds = updated.labelIds
                messageCache[messageID] = messages[idx]
            }
        } catch { self.error = error.localizedDescription }
    }

    // MARK: - Attachments helper

    func allAttachmentItems() -> [AttachmentItem] {
        emails.flatMap { email in
            email.attachments.map { attachment in
                AttachmentItem(
                    attachment:   attachment,
                    emailId:      email.id,
                    emailSubject: email.subject,
                    senderName:   email.sender.name,
                    senderColor:  email.sender.avatarColor,
                    date:         email.date,
                    direction:    email.folder == .sent ? .sent : .received
                )
            }
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: - Private fetch

    private func fetchMessages(reset: Bool, clearFirst: Bool = false) async {
        guard !accountID.isEmpty else { return }
        // clearFirst=true only on actual folder/query change → show skeleton
        if clearFirst { messages = [] }
        isLoading = true
        error     = nil
        defer { isLoading = false }
        do {
            let list = try await GmailMessageService.shared.listMessages(
                accountID: accountID,
                labelIDs:  currentLabelIDs,
                query:     currentQuery,
                pageToken: reset ? nil : nextPageToken
            )
            let refs      = list.messages ?? []
            nextPageToken = list.nextPageToken

            // Only fetch IDs not already in cache
            let idsToFetch = refs.map(\.id).filter { messageCache[$0] == nil }
            if !idsToFetch.isEmpty {
                let fetched = try await GmailMessageService.shared.getMessages(
                    ids: idsToFetch,
                    accountID: accountID,
                    format: "metadata"
                )
                for msg in fetched { messageCache[msg.id] = msg }
            }

            let page = refs.compactMap { messageCache[$0.id] }

            if reset {
                // Diff: animate only genuine additions / removals
                let pageIDs     = Set(page.map(\.id))
                let existingIDs = Set(messages.map(\.id))
                let hasChanges  = pageIDs != existingIDs

                if hasChanges {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        messages = page
                    }
                } else {
                    // Same set of messages — refresh metadata silently (read status, labels…)
                    messages = page
                }
                SubscriptionsStore.shared.analyze(page.map { makeEmail(from: $0) })
            } else {
                // Load more: append only new messages at the bottom
                let existingIDs = Set(messages.map(\.id))
                let newOnes = page.filter { !existingIDs.contains($0.id) }
                if !newOnes.isEmpty {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        messages = messages + newOnes
                    }
                    SubscriptionsStore.shared.analyze(newOnes.map { makeEmail(from: $0) })
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - GmailMessage → Email conversion

    func makeEmail(from message: GmailMessage) -> Email {
        let msgLabelIDs = message.labelIds ?? []
        let userLabels = labels.filter { !$0.isSystemLabel && msgLabelIDs.contains($0.id) }
        let emailLabels = userLabels.map { label in
            EmailLabel(
                id:    GmailDataTransformer.deterministicUUID(from: label.id),
                name:  label.displayName,
                color: label.resolvedBgColor,
                textColor: label.resolvedTextColor
            )
        }
        return Email(
            id:             GmailDataTransformer.deterministicUUID(from: message.id),
            sender:         GmailDataTransformer.parseContact(message.from),
            recipients:     GmailDataTransformer.parseContacts(message.to),
            cc:             GmailDataTransformer.parseContacts(message.cc),
            subject:        message.subject,
            body:           message.body,
            preview:        message.snippet ?? "",
            date:           message.date ?? Date(),
            isRead:         !message.isUnread,
            isStarred:      message.isStarred,
            hasAttachments: !message.attachmentParts.isEmpty,
            attachments:    message.attachmentParts.map(GmailDataTransformer.makeAttachment),
            folder:         GmailDataTransformer.folderFor(labelIDs: msgLabelIDs),
            labels:         emailLabels,
            isDraft:             message.isDraft,
            gmailMessageID:      message.id,
            gmailThreadID:       message.threadId,
            gmailLabelIDs:       msgLabelIDs,
            isFromMailingList:   message.isFromMailingList,
            unsubscribeURL:      message.unsubscribeURL
        )
    }
}
