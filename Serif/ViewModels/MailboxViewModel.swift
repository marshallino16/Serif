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

    // MARK: - Local pagination state
    /// Full set of messages loaded from disk cache.
    private var allCachedMessages: [GmailMessage] = []
    /// Current offset into allCachedMessages for local pagination.
    private var localOffset: Int = 0
    /// API page token persisted from disk cache (for resuming API pagination).
    private var savedPageToken: String?
    private let pageSize = 50

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
        // 1. Serve from local cache — skip pages with only duplicates
        while localOffset < allCachedMessages.count {
            let end = min(localOffset + pageSize, allCachedMessages.count)
            let localPage = Array(allCachedMessages[localOffset..<end])
            let existingIDs = Set(messages.map(\.id))
            let newOnes = localPage.filter { !existingIDs.contains($0.id) }
            localOffset = end
            if !newOnes.isEmpty {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    messages.append(contentsOf: newOnes)
                }
                analyzeInBackground(newOnes)
                return
            }
            // All duplicates — continue to next chunk or fall through to API
        }
        // 2. Local cache exhausted — fetch from API.
        //    Use savedPageToken (end of cache) if available, otherwise nextPageToken
        //    (from initial sync). Then skip through duplicate API pages automatically.
        if let saved = savedPageToken {
            nextPageToken  = saved
            savedPageToken = nil
        }
        guard nextPageToken != nil else { return }
        let gen = fetchGeneration // don't bump — loadMore appends, doesn't replace
        let countBefore = messages.count
        await fetchMessages(reset: false, generation: gen)
        // If API returned only duplicates, keep fetching until we get new content
        while messages.count == countBefore && nextPageToken != nil && !Task.isCancelled {
            await fetchMessages(reset: false, generation: gen)
        }
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
        allCachedMessages = []
        localOffset       = 0
        savedPageToken    = nil
        // Load disk cache for default folder (paginated)
        let folderKey = MailCacheStore.folderKey(labelIDs: currentLabelIDs, query: currentQuery)
        let cache = MailCacheStore.shared.loadFolderCache(accountID: id, folderKey: folderKey)
        if !cache.messages.isEmpty {
            allCachedMessages = cache.messages
            savedPageToken    = cache.nextPageToken
            for msg in allCachedMessages { messageCache[msg.id] = msg }
            messages    = Array(allCachedMessages.prefix(pageSize))
            localOffset = messages.count
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
            allCachedMessages.removeAll { $0.id == messageID }
            saveCacheToDisk()
        } catch { self.error = error.localizedDescription }
    }

    func archive(_ messageID: String) async {
        do {
            try await GmailMessageService.shared.archiveMessage(id: messageID, accountID: accountID)
            messages.removeAll { $0.id == messageID }   // no-op if already removed optimistically
            messageCache[messageID] = nil
            allCachedMessages.removeAll { $0.id == messageID }
            saveCacheToDisk()
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
        allCachedMessages.removeAll { $0.id == messageID }
        saveCacheToDisk()
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
        saveCacheToDisk()
        // Signal the UI to re-select this email
        lastRestoredMessageID = message.id
    }

    func emptyTrash() async {
        let backup = messages
        let cacheBackup = messageCache
        let cachedBackup = allCachedMessages
        messages.removeAll()
        messageCache.removeAll()
        allCachedMessages.removeAll()
        localOffset = 0
        saveCacheToDisk()
        do {
            try await GmailMessageService.shared.emptyTrash(accountID: accountID)
        } catch {
            messages = backup
            messageCache = cacheBackup
            allCachedMessages = cachedBackup
            saveCacheToDisk()
            self.error = error.localizedDescription
        }
    }

    func emptySpam() async {
        let backup = messages
        let cacheBackup = messageCache
        let cachedBackup = allCachedMessages
        messages.removeAll()
        messageCache.removeAll()
        allCachedMessages.removeAll()
        localOffset = 0
        saveCacheToDisk()
        do {
            try await GmailMessageService.shared.emptySpam(accountID: accountID)
        } catch {
            messages = backup
            messageCache = cacheBackup
            allCachedMessages = cachedBackup
            saveCacheToDisk()
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

    // MARK: - Background analysis (subscriptions + attachments)

    /// Fire-and-forget: analyze messages for unsubscribe links and register attachments.
    private func analyzeInBackground(_ msgs: [GmailMessage]) {
        guard !msgs.isEmpty else { return }
        SubscriptionsStore.shared.analyze(msgs.map { makeEmail(from: $0) })
        if let indexer = attachmentIndexer {
            let withAttachments = msgs.filter { !$0.attachmentParts.isEmpty }
            if !withAttachments.isEmpty {
                Task { await indexer.registerFromMetadata(messages: withAttachments) }
            }
        }
    }

    // MARK: - Disk Cache Sync

    private func saveCacheToDisk() {
        // Rebuild: displayed messages (current state) + not-yet-displayed cached messages
        let displayedIDs = Set(messages.map(\.id))
        let remaining = allCachedMessages.filter { !displayedIDs.contains($0.id) }
        allCachedMessages = messages + remaining
        let cache = FolderCache(messages: allCachedMessages, nextPageToken: savedPageToken)
        MailCacheStore.shared.saveFolderCache(cache, accountID: accountID, folderKey: currentFolderKey)
    }

    // MARK: - Private fetch

    private var currentFolderKey: String {
        MailCacheStore.folderKey(labelIDs: currentLabelIDs, query: currentQuery)
    }

    private func fetchMessages(reset: Bool, clearFirst: Bool = false, generation: UInt64) async {
        guard !accountID.isEmpty else { return }
        let folderKey = currentFolderKey

        // ── Local-first: load from disk cache and paginate locally ──
        if reset {
            let cache = MailCacheStore.shared.loadFolderCache(accountID: accountID, folderKey: folderKey)
            allCachedMessages = cache.messages
            savedPageToken    = cache.nextPageToken
            if !allCachedMessages.isEmpty {
                for msg in allCachedMessages { messageCache[msg.id] = msg }
                // Show first page instantly (no skeleton)
                let firstPage = Array(allCachedMessages.prefix(pageSize))
                localOffset   = firstPage.count
                if clearFirst || messages.isEmpty {
                    messages = firstPage
                } else {
                    // Same folder reload — only update if content differs
                    let cachedIDs   = Set(firstPage.map(\.id))
                    let currentIDs  = Set(messages.map(\.id))
                    if cachedIDs != currentIDs { messages = firstPage }
                }
                analyzeInBackground(firstPage)
            } else {
                localOffset = 0
                if clearFirst { messages = [] }
            }
        }

        isLoading = true
        error     = nil
        defer { isLoading = false }
        do {
            // ── API sync: fetch latest page to discover new messages ──
            let list = try await GmailMessageService.shared.listMessages(
                accountID: accountID,
                labelIDs:  currentLabelIDs,
                query:     currentQuery,
                pageToken: reset ? nil : (nextPageToken ?? savedPageToken)
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

                // Passive background analysis (attachments + subscriptions)
                analyzeInBackground(fetched)
            }

            // Final guard before mutating published state
            guard !Task.isCancelled, generation == fetchGeneration else { return }

            let page = refs.compactMap { messageCache[$0.id] }

            if reset {
                // Find truly new messages (from API but not in our cached set)
                let cachedIDs = Set(allCachedMessages.map(\.id))
                let newMessages = page.filter { !cachedIDs.contains($0.id) }

                if !newMessages.isEmpty {
                    // Prepend new messages to allCachedMessages and display
                    allCachedMessages.insert(contentsOf: newMessages, at: 0)
                    for msg in newMessages { messageCache[msg.id] = msg }
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        messages.insert(contentsOf: newMessages, at: 0)
                    }
                    localOffset += newMessages.count
                    analyzeInBackground(newMessages)
                }
                // Save updated cache with pagination token
                let cacheToSave = FolderCache(
                    messages: allCachedMessages,
                    nextPageToken: nextPageToken ?? savedPageToken
                )
                MailCacheStore.shared.saveFolderCache(cacheToSave, accountID: accountID, folderKey: folderKey)
            } else {
                // loadMore via API — append new messages
                let existingIDs = Set(messages.map(\.id))
                let newOnes = page.filter { !existingIDs.contains($0.id) }
                if !newOnes.isEmpty {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        messages.append(contentsOf: newOnes)
                    }
                    // Also append to allCachedMessages for future local pagination
                    let cachedIDs = Set(allCachedMessages.map(\.id))
                    let trulyNew = newOnes.filter { !cachedIDs.contains($0.id) }
                    allCachedMessages.append(contentsOf: trulyNew)
                    localOffset = allCachedMessages.count
                    analyzeInBackground(newOnes)
                }
                // Update savedPageToken and persist
                savedPageToken = nextPageToken
                let cacheToSave = FolderCache(
                    messages: allCachedMessages,
                    nextPageToken: nextPageToken
                )
                MailCacheStore.shared.saveFolderCache(cacheToSave, accountID: accountID, folderKey: folderKey)
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
