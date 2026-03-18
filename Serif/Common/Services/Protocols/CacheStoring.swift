import Foundation

/// Abstracts the mail cache read/write interface so services
/// can be tested with in-memory mock caches.
protocol CacheStoring {
    // MARK: - Folder cache (messages + pagination metadata)
    func loadFolderCache(accountID: String, folderKey: String) -> FolderCache
    func saveFolderCache(_ cache: FolderCache, accountID: String, folderKey: String)

    // MARK: - Legacy message accessors
    func load(accountID: String, folderKey: String) -> [GmailMessage]
    func save(_ messages: [GmailMessage], accountID: String, folderKey: String)

    // MARK: - Labels
    func loadLabels(accountID: String) -> [GmailLabel]
    func saveLabels(_ labels: [GmailLabel], accountID: String)

    // MARK: - Threads
    func loadThread(accountID: String, threadID: String) -> GmailThread?
    func saveThread(_ thread: GmailThread, accountID: String)

    // MARK: - Account deletion
    func deleteAccount(_ accountID: String)
}

// MARK: - MailCacheStore conformance

extension MailCacheStore: CacheStoring {}
