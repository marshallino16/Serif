import SwiftUI

/// Drives the email list for a given account and folder.
@MainActor
final class MailboxViewModel: ObservableObject {
    @Published var messages:      [GmailMessage] = []
    @Published var isLoading      = false
    @Published var error:         String?
    @Published var nextPageToken: String?
    @Published var labels:                [GmailLabel] = []
    @Published var sendAsAliases:         [GmailSendAs] = []
    @Published var readIDs:               Set<String> = []
    @Published var categoryUnreadCounts:  [InboxCategory: Int] = [:]
    /// Set by `restoreOptimistically` so the UI can re-select the restored email.
    @Published var lastRestoredMessageID: String?

    var accountID: String
    var attachmentIndexer: AttachmentIndexer?
    private var currentLabelIDs: [String] = ["INBOX"]
    private var currentQuery:    String?
    /// In-memory cache of fetched messages (metadata format) keyed by message ID.
    private var messageCache: [String: GmailMessage] = [:]
    /// Tracks the current fetch task so it can be cancelled when a new one starts.
    private var activeFetchTask: Task<Void, Never>?
    /// Monotonically increasing token to discard stale results from races.
    private var fetchGeneration: UInt64 = 0

    init(accountID: String) {
        self.accountID = accountID
    }

    // MARK: - GmailMessage → Email (computed)

    var emails: [Email] {
        messages.map { makeEmail(from: $0) }
    }

    // MARK: - Load

    /// Cancels any in-flight fetch and starts a new folder load.
    func loadFolder(labelIDs: [String], query: String? = nil) async {
        let isFolderChange = labelIDs != currentLabelIDs || query != currentQuery
        currentLabelIDs = labelIDs
        currentQuery    = query
        cancelActiveFetch()
        let gen = nextGeneration()
        activeFetchTask = Task {
            await fetchMessages(reset: true, clearFirst: isFolderChange, generation: gen)
        }
        await activeFetchTask?.value
    }

    /// Cancels any in-flight fetch and starts a new search.
    func search(query: String) async {
        let newQuery = query.isEmpty ? nil : query
        let isNewQuery = newQuery != currentQuery
        currentQuery = newQuery
        cancelActiveFetch()
        let gen = nextGeneration()
        activeFetchTask = Task {
            await fetchMessages(reset: true, clearFirst: isNewQuery, generation: gen)
        }
        await activeFetchTask?.value
    }

    func loadMore() async {
        guard nextPageToken != nil else { return }
        let gen = fetchGeneration // don't bump — loadMore appends, doesn't replace
        await fetchMessages(reset: false, generation: gen)
    }

    /// Cancel any in-flight search/load task. Called from the view layer
    /// when a new search or folder navigation begins.
    func cancelActiveFetch() {
        activeFetchTask?.cancel()
        activeFetchTask = nil
    }

    private func nextGeneration() -> UInt64 {
        fetchGeneration &+= 1
        return fetchGeneration
    }

    func loadLabels() async {
        // Load from disk cache first
        let cached = MailCacheStore.shared.loadLabels(accountID: accountID)
        if !cached.isEmpty && labels.isEmpty {
            labels = cached
        }
        // Refresh from API
        do {
            let fresh = try await GmailLabelService.shared.listLabels(accountID: accountID)
            labels = fresh
            MailCacheStore.shared.saveLabels(fresh, accountID: accountID)
        } catch {
            // Keep cached labels if API fails
            if labels.isEmpty { self.error = error.localizedDescription }
        }
    }

    func loadSendAs() async {
        do { sendAsAliases = try await GmailProfileService.shared.listSendAs(accountID: accountID) }
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
        cancelActiveFetch()
        accountID     = id
        nextPageToken = nil
        readIDs       = []
        error         = nil
        messageCache  = [:]
        // Load disk cache for default folder
        let folderKey = MailCacheStore.folderKey(labelIDs: currentLabelIDs, query: currentQuery)
        let cached = MailCacheStore.shared.load(accountID: id, folderKey: folderKey)
        if !cached.isEmpty {
            for msg in cached { messageCache[msg.id] = msg }
            messages = cached
            // Index cached attachments on account switch
            if let indexer = attachmentIndexer {
                let cachedEmails = cached.map { makeEmail(from: $0) }
                let pairs = cachedEmails.flatMap { email in
                    email.attachments.map { (attachment: $0, email: email) }
                }
                if !pairs.isEmpty {
                    Task { await indexer.register(attachments: pairs) }
                }
            }
        } else {
            messages = []
        }
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
        // Restore into the in-memory cache so subsequent lookups work
        messageCache[message.id] = message
        let date = message.date ?? .distantPast
        let insertIdx = messages.firstIndex { ($0.date ?? .distantPast) < date } ?? messages.endIndex
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            messages.insert(message, at: insertIdx)
        }
        // Signal the UI to re-select this email
        lastRestoredMessageID = message.id
    }

    func emptyTrash() async {
        let backup = messages
        let cacheBackup = messageCache
        messages.removeAll()
        messageCache.removeAll()
        do {
            try await GmailMessageService.shared.emptyTrash(accountID: accountID)
        } catch {
            messages = backup
            messageCache = cacheBackup
            self.error = error.localizedDescription
        }
    }

    func moveToInbox(_ messageID: String) async {
        do {
            try await GmailMessageService.shared.modifyLabels(
                id: messageID, add: ["INBOX"], remove: [], accountID: accountID
            )
            messages.removeAll { $0.id == messageID }
            messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    func untrash(_ messageID: String) async {
        do {
            try await GmailMessageService.shared.untrashMessage(id: messageID, accountID: accountID)
            try await GmailMessageService.shared.modifyLabels(
                id: messageID, add: ["INBOX"], remove: [], accountID: accountID
            )
            messages.removeAll { $0.id == messageID }
            messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    func deletePermanently(_ messageID: String) async {
        do {
            try await GmailMessageService.shared.deleteMessagePermanently(id: messageID, accountID: accountID)
            messages.removeAll { $0.id == messageID }
            messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    func unspam(_ messageID: String) async {
        do {
            try await GmailMessageService.shared.modifyLabels(
                id: messageID, add: ["INBOX"], remove: ["SPAM"], accountID: accountID
            )
            messages.removeAll { $0.id == messageID }
            messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
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

    @discardableResult
    func createAndAddLabel(name: String, to messageID: String) async -> String? {
        do {
            let newLabel = try await GmailLabelService.shared.createLabel(name: name, accountID: accountID)
            labels.append(newLabel)
            await addLabel(newLabel.id, to: messageID)
            // Force re-computation of emails (computed depends on both messages and labels)
            objectWillChange.send()
            return newLabel.id
        } catch {
            self.error = error.localizedDescription
            return nil
        }
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

    private var currentFolderKey: String {
        MailCacheStore.folderKey(labelIDs: currentLabelIDs, query: currentQuery)
    }

    private func fetchMessages(reset: Bool, clearFirst: Bool = false, generation: UInt64) async {
        guard !accountID.isEmpty else { return }
        let folderKey = currentFolderKey

        // Pre-populate in-memory cache from disk (avoids re-fetching known messages)
        if reset {
            let cached = MailCacheStore.shared.load(accountID: accountID, folderKey: folderKey)
            if !cached.isEmpty {
                for msg in cached { messageCache[msg.id] = msg }
                // Show cached messages instantly on folder change (no skeleton)
                if clearFirst { messages = cached }
                // Index cached attachments immediately
                if let indexer = attachmentIndexer {
                    let cachedEmails = cached.map { makeEmail(from: $0) }
                    let pairs = cachedEmails.flatMap { email in
                        email.attachments.map { (attachment: $0, email: email) }
                    }
                    if !pairs.isEmpty {
                        Task { await indexer.register(attachments: pairs) }
                    }
                }
            } else if clearFirst {
                messages = []
            }
        }

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

            // Bail out if a newer request has started while we were awaiting
            guard !Task.isCancelled, generation == fetchGeneration else { return }

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
                // Check again after second await
                guard !Task.isCancelled, generation == fetchGeneration else { return }
                for msg in fetched { messageCache[msg.id] = msg }
            }

            // Final guard before mutating published state
            guard !Task.isCancelled, generation == fetchGeneration else { return }

            let page = refs.compactMap { messageCache[$0.id] }

            if reset {
                let pageIDs     = Set(page.map(\.id))
                let existingIDs = Set(messages.map(\.id))
                let hasChanges  = pageIDs != existingIDs

                if hasChanges {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        messages = page
                    }
                } else {
                    messages = page
                }
                SubscriptionsStore.shared.analyze(page.map { makeEmail(from: $0) })
                // Persist to disk
                MailCacheStore.shared.save(page, accountID: accountID, folderKey: folderKey)
            } else {
                let existingIDs = Set(messages.map(\.id))
                let newOnes = page.filter { !existingIDs.contains($0.id) }
                if !newOnes.isEmpty {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        messages = messages + newOnes
                    }
                    SubscriptionsStore.shared.analyze(newOnes.map { makeEmail(from: $0) })
                }
                // Persist full list to disk
                MailCacheStore.shared.save(messages, accountID: accountID, folderKey: folderKey)
            }

            // Register attachments for indexing
            if let indexer = attachmentIndexer {
                let emailsList = self.emails
                let pairs = emailsList.flatMap { email in
                    email.attachments.map { (attachment: $0, email: email) }
                }
                if !pairs.isEmpty {
                    Task { await indexer.register(attachments: pairs) }
                }
            }
        } catch is CancellationError {
            // Silently swallow — a newer request replaced us
        } catch {
            // Only surface the error if this is still the active generation
            guard generation == fetchGeneration else { return }
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
            attachments:    message.attachmentParts.map { GmailDataTransformer.makeAttachment(from: $0, messageId: message.id) },
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
