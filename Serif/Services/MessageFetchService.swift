import SwiftUI

/// Handles message fetching, pagination, and disk caching for a mailbox.
/// Owns the internal cache state; the MailboxViewModel orchestrates the
/// fetch flow and applies results to its @Published properties.
@MainActor
final class MessageFetchService {

    // MARK: - Injected dependencies

    private let api: MessageFetching
    private let cache: CacheStoring

    // MARK: - Dependencies (set by MailboxViewModel)

    /// Called to convert a GmailMessage into an Email for background analysis.
    var makeEmail: ((GmailMessage) -> Email)?
    /// Reference to the attachment indexer (if configured).
    var attachmentIndexer: AttachmentIndexer?

    // MARK: - Internal cache state

    /// In-memory cache of fetched messages (metadata format) keyed by message ID.
    var messageCache: [String: GmailMessage] = [:]
    /// Full set of messages loaded from disk cache.
    var allCachedMessages: [GmailMessage] = []
    /// Current offset into allCachedMessages for local pagination.
    var localOffset: Int = 0
    /// API page token persisted from disk cache (for resuming API pagination).
    var savedPageToken: String?
    let pageSize = 50

    init(api: MessageFetching = GmailMessageService.shared, cache: CacheStoring = MailCacheStore.shared) {
        self.api = api
        self.cache = cache
    }

    /// Tracks the current fetch task so it can be cancelled when a new one starts.
    private var activeFetchTask: Task<Void, Never>?
    /// Monotonically increasing token to discard stale results from races.
    private var fetchGeneration: UInt64 = 0

    // MARK: - Task management

    func cancelActiveFetch() {
        activeFetchTask?.cancel()
        activeFetchTask = nil
    }

    func setActiveFetchTask(_ task: Task<Void, Never>) {
        activeFetchTask = task
    }

    func awaitActiveFetch() async {
        await activeFetchTask?.value
    }

    func nextGeneration() -> UInt64 {
        fetchGeneration &+= 1
        return fetchGeneration
    }

    var currentGeneration: UInt64 { fetchGeneration }

    func isStale(generation: UInt64) -> Bool {
        Task.isCancelled || generation != fetchGeneration
    }

    // MARK: - Cache loading (synchronous, for local-first display)

    /// Loads the disk cache for a folder and returns the first page for display.
    /// Updates internal cache state (allCachedMessages, savedPageToken, localOffset).
    func loadDiskCache(
        accountID: String,
        folderKey: String
    ) -> (firstPage: [GmailMessage], hasCachedMessages: Bool) {
        let diskCache = cache.loadFolderCache(accountID: accountID, folderKey: folderKey)
        allCachedMessages = diskCache.messages
        savedPageToken    = diskCache.nextPageToken
        if !allCachedMessages.isEmpty {
            for msg in allCachedMessages { messageCache[msg.id] = msg }
            let firstPage = Array(allCachedMessages.prefix(pageSize))
            localOffset   = firstPage.count
            return (firstPage, true)
        }
        localOffset = 0
        return ([], false)
    }

    // MARK: - API fetch helpers

    /// Fetches the message list from the API.
    func listMessages(
        accountID: String,
        currentLabelIDs: [String],
        currentQuery: String?,
        pageToken: String?
    ) async throws -> GmailMessageListResponse {
        try await api.listMessages(
            accountID: accountID,
            labelIDs:  currentLabelIDs,
            query:     currentQuery,
            pageToken: pageToken,
            maxResults: pageSize
        )
    }

    /// Fetches full metadata for message IDs not already in the cache.
    /// Returns the newly fetched messages.
    func fetchMissingMessages(
        refs: [GmailMessageRef],
        accountID: String
    ) async throws -> [GmailMessage] {
        let idsToFetch = refs.map(\.id).filter { messageCache[$0] == nil }
        guard !idsToFetch.isEmpty else { return [] }
        let fetched = try await api.getMessages(
            ids: idsToFetch,
            accountID: accountID,
            format: "metadata"
        )
        for msg in fetched { messageCache[msg.id] = msg }
        return fetched
    }

    /// Resolves message refs to full GmailMessage objects using the cache.
    func resolveFromCache(_ refs: [GmailMessageRef]) -> [GmailMessage] {
        refs.compactMap { messageCache[$0.id] }
    }

    /// Finds messages in `page` that are not already in `allCachedMessages`.
    func findNewMessages(in page: [GmailMessage]) -> [GmailMessage] {
        let cachedIDs = Set(allCachedMessages.map(\.id))
        return page.filter { !cachedIDs.contains($0.id) }
    }

    /// Prepends new messages to the internal cache and adjusts the local offset.
    func prependToCache(_ newMessages: [GmailMessage]) {
        allCachedMessages.insert(contentsOf: newMessages, at: 0)
        for msg in newMessages { messageCache[msg.id] = msg }
        localOffset += newMessages.count
    }

    /// Appends new messages to the internal cache (for loadMore via API).
    func appendToCache(_ newOnes: [GmailMessage]) {
        let cachedIDs = Set(allCachedMessages.map(\.id))
        let trulyNew = newOnes.filter { !cachedIDs.contains($0.id) }
        allCachedMessages.append(contentsOf: trulyNew)
        localOffset = allCachedMessages.count
    }

    /// Persists the current cache state to disk.
    func persistCache(
        accountID: String,
        folderKey: String,
        nextPageToken: String?
    ) {
        let cacheToSave = FolderCache(
            messages: allCachedMessages,
            nextPageToken: nextPageToken ?? savedPageToken
        )
        cache.saveFolderCache(cacheToSave, accountID: accountID, folderKey: folderKey)
    }

    /// Updates savedPageToken and persists the cache (for loadMore).
    func persistCacheAfterLoadMore(
        accountID: String,
        folderKey: String,
        nextPageToken: String?
    ) {
        savedPageToken = nextPageToken
        let cacheToSave = FolderCache(
            messages: allCachedMessages,
            nextPageToken: nextPageToken
        )
        cache.saveFolderCache(cacheToSave, accountID: accountID, folderKey: folderKey)
    }

    // MARK: - Load more (local pagination)

    /// Attempts to serve the next page from the local disk cache.
    /// Returns the new messages to append, or nil if the local cache is exhausted.
    func loadMoreFromLocalCache(currentMessages: [GmailMessage]) -> [GmailMessage]? {
        while localOffset < allCachedMessages.count {
            let end = min(localOffset + pageSize, allCachedMessages.count)
            let localPage = Array(allCachedMessages[localOffset..<end])
            let existingIDs = Set(currentMessages.map(\.id))
            let newOnes = localPage.filter { !existingIDs.contains($0.id) }
            localOffset = end
            if !newOnes.isEmpty {
                return newOnes
            }
            // All duplicates — continue to next chunk or fall through to API
        }
        return nil // local cache exhausted
    }

    /// Promotes the saved page token (end-of-cache) to the active nextPageToken.
    /// Returns the promoted token, or nil if there was no saved token.
    func promoteSavedPageToken() -> String? {
        guard let saved = savedPageToken else { return nil }
        savedPageToken = nil
        return saved
    }

    // MARK: - Disk cache sync

    func saveCacheToDisk(
        messages: [GmailMessage],
        accountID: String,
        currentLabelIDs: [String],
        currentQuery: String?
    ) {
        // Rebuild: displayed messages (current state) + not-yet-displayed cached messages
        let displayedIDs = Set(messages.map(\.id))
        let remaining = allCachedMessages.filter { !displayedIDs.contains($0.id) }
        allCachedMessages = messages + remaining
        let folderKey = MailCacheStore.folderKey(labelIDs: currentLabelIDs, query: currentQuery)
        let folderCache = FolderCache(messages: allCachedMessages, nextPageToken: savedPageToken)
        cache.saveFolderCache(folderCache, accountID: accountID, folderKey: folderKey)
    }

    // MARK: - Background analysis (subscriptions + attachments)

    func analyzeInBackground(_ msgs: [GmailMessage]) {
        guard !msgs.isEmpty, let makeEmail = makeEmail else { return }
        SubscriptionsStore.shared.analyze(msgs.map { makeEmail($0) })
        if let indexer = attachmentIndexer {
            let withAttachments = msgs.filter { $0.hasPartsWithFilenames }
            if !withAttachments.isEmpty {
                Task { await indexer.registerFromMetadata(messages: withAttachments) }
            }
        }
    }

    // MARK: - Reset (for account switch)

    func resetState() {
        messageCache      = [:]
        allCachedMessages = []
        localOffset       = 0
        savedPageToken    = nil
    }

    /// Loads the disk cache for a given folder, returning the first page of messages.
    func loadCacheForAccountSwitch(
        accountID: String,
        currentLabelIDs: [String],
        currentQuery: String?
    ) -> [GmailMessage] {
        let folderKey = MailCacheStore.folderKey(labelIDs: currentLabelIDs, query: currentQuery)
        let diskCache = cache.loadFolderCache(accountID: accountID, folderKey: folderKey)
        if !diskCache.messages.isEmpty {
            allCachedMessages = diskCache.messages
            savedPageToken    = diskCache.nextPageToken
            for msg in allCachedMessages { messageCache[msg.id] = msg }
            let first = Array(allCachedMessages.prefix(pageSize))
            localOffset = first.count
            return first
        }
        return []
    }
}
