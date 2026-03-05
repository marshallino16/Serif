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
    var attachmentIndexer: AttachmentIndexer? {
        didSet { fetchService.attachmentIndexer = attachmentIndexer }
    }
    private var currentLabelIDs: [String] = ["INBOX"]
    private var currentQuery:    String?

    // MARK: - Services

    private let api: MessageFetching
    private let fetchService: MessageFetchService
    private let labelService: LabelSyncService
    private let historyService: HistorySyncService

    init(
        accountID: String,
        api: MessageFetching = GmailMessageService.shared,
        cache: CacheStoring = MailCacheStore.shared
    ) {
        self.accountID = accountID
        self.api = api
        self.fetchService   = MessageFetchService(api: api, cache: cache)
        self.labelService   = LabelSyncService(cache: cache)
        self.historyService = HistorySyncService(api: api)
        // Wire up the makeEmail closure for background analysis.
        // Uses unowned since the service cannot outlive the VM that owns it.
        fetchService.makeEmail = { [unowned self] msg in
            self.makeEmail(from: msg)
        }
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
        let gen = fetchService.nextGeneration()
        fetchService.setActiveFetchTask(Task {
            await self.performFetch(reset: true, clearFirst: isFolderChange, generation: gen)
        })
        await fetchService.awaitActiveFetch()
    }

    /// Cancels any in-flight fetch and starts a new search.
    func search(query: String) async {
        let newQuery = query.isEmpty ? nil : query
        let isNewQuery = newQuery != currentQuery
        currentQuery = newQuery
        cancelActiveFetch()
        let gen = fetchService.nextGeneration()
        fetchService.setActiveFetchTask(Task {
            await self.performFetch(reset: true, clearFirst: isNewQuery, generation: gen)
        })
        await fetchService.awaitActiveFetch()
    }

    func loadMore() async {
        // 1. Serve from local cache — skip pages with only duplicates
        if let newOnes = fetchService.loadMoreFromLocalCache(currentMessages: messages) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                messages.append(contentsOf: newOnes)
            }
            fetchService.analyzeInBackground(newOnes)
            return
        }
        // 2. Local cache exhausted — fetch from API.
        if let promoted = fetchService.promoteSavedPageToken() {
            nextPageToken = promoted
        }
        guard nextPageToken != nil else { return }
        let gen = fetchService.currentGeneration // don't bump — loadMore appends, doesn't replace
        let countBefore = messages.count
        await performFetch(reset: false, generation: gen)
        // If API returned only duplicates, keep fetching until we get new content
        while messages.count == countBefore && nextPageToken != nil && !Task.isCancelled {
            await performFetch(reset: false, generation: gen)
        }
    }

    /// Cancel any in-flight search/load task. Called from the view layer
    /// when a new search or folder navigation begins.
    func cancelActiveFetch() {
        fetchService.cancelActiveFetch()
    }

    // MARK: - Labels & Metadata

    func loadLabels() async {
        let result = await labelService.loadLabels(accountID: accountID, currentLabels: labels)
        labels = result.labels
        if let err = result.error { error = err }
    }

    func loadSendAs() async {
        let result = await labelService.loadSendAs(accountID: accountID)
        sendAsAliases = result.aliases
        if let err = result.error { error = err }
    }

    func renameLabel(_ label: GmailLabel, to newName: String) async {
        if let idx = labels.firstIndex(where: { $0.id == label.id }) {
            let updated = GmailLabel(id: label.id, name: newName, type: label.type,
                                      messagesTotal: label.messagesTotal, messagesUnread: label.messagesUnread,
                                      threadsTotal: label.threadsTotal, threadsUnread: label.threadsUnread,
                                      color: label.color)
            labels[idx] = updated
        }
        do {
            let fresh = try await GmailLabelService.shared.updateLabel(id: label.id, newName: newName, accountID: accountID)
            if let idx = labels.firstIndex(where: { $0.id == fresh.id }) { labels[idx] = fresh }
        } catch {
            if let idx = labels.firstIndex(where: { $0.id == label.id }) { labels[idx] = label }
            self.error = error.localizedDescription
        }
    }

    func deleteLabel(_ label: GmailLabel) async {
        let backup = labels
        labels.removeAll { $0.id == label.id }
        do {
            try await GmailLabelService.shared.deleteLabel(id: label.id, accountID: accountID)
        } catch {
            labels = backup
            self.error = error.localizedDescription
        }
    }

    func loadCategoryUnreadCounts() async {
        categoryUnreadCounts = await labelService.loadCategoryUnreadCounts(accountID: accountID)
    }

    // MARK: - Account switching

    func switchAccount(_ id: String) async {
        cancelActiveFetch()
        accountID     = id
        nextPageToken = nil
        readIDs       = []
        error         = nil
        fetchService.resetState()
        // Load disk cache for default folder (paginated)
        let cached = fetchService.loadCacheForAccountSwitch(
            accountID: id,
            currentLabelIDs: currentLabelIDs,
            currentQuery: currentQuery
        )
        messages = cached.isEmpty ? [] : cached
    }

    // MARK: - Delta Sync via History API

    /// Refreshes the current folder using delta sync when possible,
    /// falling back to full re-fetch.
    func refreshCurrentFolder(labelIDs: [String], query: String? = nil) async {
        let isSameFolder = labelIDs == currentLabelIDs && query == currentQuery

        // Only attempt delta sync if:
        // 1. Same folder (not a folder switch)
        // 2. No search query (history API doesn't support queries)
        // 3. We have cached messages (not first load)
        // 4. Single label ID or no label (history API filters by one label)
        if isSameFolder && query == nil && !fetchService.allCachedMessages.isEmpty && labelIDs.count <= 1 {
            let success = await applyHistorySync(labelId: labelIDs.first)
            if success { return }
        }

        // Full refresh (existing path)
        await loadFolder(labelIDs: labelIDs, query: query)
    }

    // MARK: - Mutations

    func markAsRead(_ message: GmailMessage) async {
        guard message.isUnread && !readIDs.contains(message.id) else { return }
        readIDs.insert(message.id)
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx].labelIds?.removeAll { $0 == "UNREAD" }
            fetchService.messageCache[message.id] = messages[idx]
        }
        try? await api.markAsRead(id: message.id, accountID: accountID)
    }

    func markAsUnread(_ messageID: String) async {
        if let idx = messages.firstIndex(where: { $0.id == messageID }) {
            if messages[idx].labelIds?.contains("UNREAD") == false {
                messages[idx].labelIds?.append("UNREAD")
            }
            fetchService.messageCache[messageID] = messages[idx]
        }
        readIDs.remove(messageID)
        do {
            try await api.markAsUnread(id: messageID, accountID: accountID)
        } catch { self.error = error.localizedDescription }
    }

    func toggleStar(_ messageID: String, isStarred: Bool) async {
        if let idx = messages.firstIndex(where: { $0.id == messageID }) {
            if isStarred {
                messages[idx].labelIds?.removeAll { $0 == "STARRED" }
            } else {
                messages[idx].labelIds?.append("STARRED")
            }
            fetchService.messageCache[messageID] = messages[idx]
        }
        do {
            try await api.setStarred(!isStarred, id: messageID, accountID: accountID)
        } catch {
            // Revert on failure
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                if isStarred {
                    messages[idx].labelIds?.append("STARRED")
                } else {
                    messages[idx].labelIds?.removeAll { $0 == "STARRED" }
                }
                fetchService.messageCache[messageID] = messages[idx]
            }
            self.error = error.localizedDescription
        }
    }

    func trash(_ messageID: String) async {
        do {
            try await api.trashMessage(id: messageID, accountID: accountID)
            messages.removeAll { $0.id == messageID }   // no-op if already removed optimistically
            fetchService.messageCache[messageID] = nil
            fetchService.allCachedMessages.removeAll { $0.id == messageID }
            saveCacheToDisk()
        } catch { self.error = error.localizedDescription }
    }

    func archive(_ messageID: String) async {
        do {
            try await api.archiveMessage(id: messageID, accountID: accountID)
            messages.removeAll { $0.id == messageID }   // no-op if already removed optimistically
            fetchService.messageCache[messageID] = nil
            fetchService.allCachedMessages.removeAll { $0.id == messageID }
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
        fetchService.allCachedMessages.removeAll { $0.id == messageID }
        saveCacheToDisk()
        return msg
    }

    /// Re-inserts a previously removed message at its original date position (undo path).
    func restoreOptimistically(_ message: GmailMessage) {
        // Restore into the in-memory cache so subsequent lookups work
        fetchService.messageCache[message.id] = message
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
        let cacheBackup = fetchService.messageCache
        let cachedBackup = fetchService.allCachedMessages
        messages.removeAll()
        fetchService.messageCache.removeAll()
        fetchService.allCachedMessages.removeAll()
        fetchService.localOffset = 0
        saveCacheToDisk()
        do {
            try await api.emptyTrash(accountID: accountID)
        } catch {
            messages = backup
            fetchService.messageCache = cacheBackup
            fetchService.allCachedMessages = cachedBackup
            saveCacheToDisk()
            self.error = error.localizedDescription
        }
    }

    func emptySpam() async {
        let backup = messages
        let cacheBackup = fetchService.messageCache
        let cachedBackup = fetchService.allCachedMessages
        messages.removeAll()
        fetchService.messageCache.removeAll()
        fetchService.allCachedMessages.removeAll()
        fetchService.localOffset = 0
        saveCacheToDisk()
        do {
            try await api.emptySpam(accountID: accountID)
        } catch {
            messages = backup
            fetchService.messageCache = cacheBackup
            fetchService.allCachedMessages = cachedBackup
            saveCacheToDisk()
            self.error = error.localizedDescription
        }
    }

    func moveToInbox(_ messageID: String) async {
        do {
            try await api.modifyLabels(
                id: messageID, add: ["INBOX"], remove: [], accountID: accountID
            )
            messages.removeAll { $0.id == messageID }
            fetchService.messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    func untrash(_ messageID: String) async {
        do {
            try await api.untrashMessage(id: messageID, accountID: accountID)
            try await api.modifyLabels(
                id: messageID, add: ["INBOX"], remove: [], accountID: accountID
            )
            messages.removeAll { $0.id == messageID }
            fetchService.messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    func deletePermanently(_ messageID: String) async {
        do {
            try await api.deleteMessagePermanently(id: messageID, accountID: accountID)
            messages.removeAll { $0.id == messageID }
            fetchService.messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    func unspam(_ messageID: String) async {
        do {
            try await api.modifyLabels(
                id: messageID, add: ["INBOX"], remove: ["SPAM"], accountID: accountID
            )
            messages.removeAll { $0.id == messageID }
            fetchService.messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    func spam(_ messageID: String) async {
        do {
            try await api.spamMessage(id: messageID, accountID: accountID)
            messages.removeAll { $0.id == messageID }
            fetchService.messageCache[messageID] = nil
        } catch { self.error = error.localizedDescription }
    }

    func addLabel(_ labelID: String, to messageID: String) async {
        do {
            let updated = try await api.modifyLabels(
                id: messageID, add: [labelID], remove: [], accountID: accountID
            )
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                messages[idx].labelIds = updated.labelIds
                fetchService.messageCache[messageID] = messages[idx]
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
            let updated = try await api.modifyLabels(
                id: messageID, add: [], remove: [labelID], accountID: accountID
            )
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                messages[idx].labelIds = updated.labelIds
                fetchService.messageCache[messageID] = messages[idx]
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

    // MARK: - Private fetch orchestration

    private var currentFolderKey: String {
        MailCacheStore.folderKey(labelIDs: currentLabelIDs, query: currentQuery)
    }

    private func performFetch(reset: Bool, clearFirst: Bool = false, generation: UInt64) async {
        guard !accountID.isEmpty else { return }
        let folderKey = currentFolderKey

        // ── Local-first: load from disk cache and paginate locally ──
        if reset {
            let (firstPage, hasCached) = fetchService.loadDiskCache(accountID: accountID, folderKey: folderKey, filterLabelIDs: currentLabelIDs)
            if hasCached {
                if clearFirst || messages.isEmpty {
                    messages = firstPage
                } else {
                    let cachedIDs  = Set(firstPage.map(\.id))
                    let currentIDs = Set(messages.map(\.id))
                    if cachedIDs != currentIDs { messages = firstPage }
                }
                fetchService.analyzeInBackground(firstPage)
            } else {
                if clearFirst { messages = [] }
            }
        }

        isLoading = true
        error     = nil
        defer { isLoading = false }
        do {
            // ── API sync: fetch latest page to discover new messages ──
            let list = try await fetchService.listMessages(
                accountID: accountID,
                currentLabelIDs: currentLabelIDs,
                currentQuery: currentQuery,
                pageToken: reset ? nil : (nextPageToken ?? fetchService.savedPageToken)
            )

            guard !fetchService.isStale(generation: generation) else { return }

            let refs = list.messages ?? []
            nextPageToken = list.nextPageToken

            let fetched = try await fetchService.fetchMissingMessages(refs: refs, accountID: accountID)

            guard !fetchService.isStale(generation: generation) else { return }

            if !fetched.isEmpty {
                fetchService.analyzeInBackground(fetched)
            }

            guard !fetchService.isStale(generation: generation) else { return }

            let page = fetchService.resolveFromCache(refs)

            if reset {
                let newMessages = fetchService.findNewMessages(in: page)
                if !newMessages.isEmpty {
                    fetchService.prependToCache(newMessages)
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        messages.insert(contentsOf: newMessages, at: 0)
                    }
                    fetchService.analyzeInBackground(newMessages)
                }

                // Prune stale messages: locally cached but absent from the API's first page.
                // Verify each suspect with a lightweight API call to distinguish
                // "deleted/moved" from "pushed to next page".
                if !refs.isEmpty {
                    let serverIDs = Set(refs.map(\.id))
                    let suspectIDs = messages.filter { !serverIDs.contains($0.id) }.map(\.id)
                    if !suspectIDs.isEmpty {
                        var staleIDs: [String] = []
                        let folderLabels = Set(currentLabelIDs)
                        for id in suspectIDs {
                            guard !fetchService.isStale(generation: generation) else { break }
                            do {
                                let msg = try await api.getMessage(id: id, accountID: accountID, format: "minimal")
                                // Exists but moved to a different folder
                                if !folderLabels.isEmpty,
                                   let msgLabels = msg.labelIds,
                                   folderLabels.isDisjoint(with: Set(msgLabels)) {
                                    staleIDs.append(id)
                                }
                            } catch {
                                staleIDs.append(id) // 404 → deleted on Gmail
                            }
                        }
                        if !staleIDs.isEmpty {
                            let staleSet = Set(staleIDs)
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                messages.removeAll { staleSet.contains($0.id) }
                            }
                            fetchService.allCachedMessages.removeAll { staleSet.contains($0.id) }
                            for id in staleIDs { fetchService.messageCache[id] = nil }
                        }
                    }
                }

                fetchService.persistCache(accountID: accountID, folderKey: folderKey, nextPageToken: nextPageToken)

                if let latestHistoryId = page.compactMap(\.historyId).first {
                    historyService.updateStoredHistoryId(latestHistoryId, accountID: accountID)
                }
            } else {
                // loadMore via API — append new messages
                let existingIDs = Set(messages.map(\.id))
                let newOnes = page.filter { !existingIDs.contains($0.id) }
                if !newOnes.isEmpty {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        messages.append(contentsOf: newOnes)
                    }
                    fetchService.appendToCache(newOnes)
                    fetchService.analyzeInBackground(newOnes)
                }
                fetchService.persistCacheAfterLoadMore(accountID: accountID, folderKey: folderKey, nextPageToken: nextPageToken)
            }

        } catch is CancellationError {
            // Silently swallow — a newer request replaced us
        } catch {
            guard !fetchService.isStale(generation: generation) else { return }
            self.error = error.localizedDescription
        }
    }

    /// Applies the result of a history sync to the VM's published state.
    private func applyHistorySync(labelId: String?) async -> Bool {
        let existingIDs = Set(messages.map(\.id))
        let result = await historyService.syncViaHistory(
            accountID: accountID,
            labelId: labelId,
            existingMessageIDs: existingIDs
        )
        guard result.succeeded else { return false }

        // Remove deleted messages from cache + UI
        if !result.deletedIDs.isEmpty {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                messages.removeAll { result.deletedIDs.contains($0.id) }
            }
            fetchService.allCachedMessages.removeAll { result.deletedIDs.contains($0.id) }
            for id in result.deletedIDs { fetchService.messageCache[id] = nil }
        }

        // Insert new messages (already filtered by the service against existingIDs)
        if !result.newMessages.isEmpty {
            for msg in result.newMessages { fetchService.messageCache[msg.id] = msg }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                messages.insert(contentsOf: result.newMessages, at: 0)
            }
            fetchService.allCachedMessages.insert(contentsOf: result.newMessages, at: 0)
            fetchService.localOffset += result.newMessages.count
            fetchService.analyzeInBackground(result.newMessages)
        }

        // Apply label changes to existing messages
        for msg in result.refreshedMessages {
            fetchService.messageCache[msg.id] = msg
            // If the message lost the current folder's label, remove it
            if let labelId, let msgLabels = msg.labelIds, !msgLabels.contains(labelId) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    messages.removeAll { $0.id == msg.id }
                }
                fetchService.allCachedMessages.removeAll { $0.id == msg.id }
                fetchService.messageCache[msg.id] = nil
            } else {
                if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
                    messages[idx] = msg
                }
                if let idx = fetchService.allCachedMessages.firstIndex(where: { $0.id == msg.id }) {
                    fetchService.allCachedMessages[idx] = msg
                }
            }
        }

        // Save updated cache
        saveCacheToDisk()

        // Persist the new historyId
        if let historyId = result.latestHistoryId {
            historyService.updateStoredHistoryId(historyId, accountID: accountID)
        }

        if let err = result.error { error = err }
        return true
    }

    private func saveCacheToDisk() {
        fetchService.saveCacheToDisk(
            messages: messages,
            accountID: accountID,
            currentLabelIDs: currentLabelIDs,
            currentQuery: currentQuery
        )
    }
}
