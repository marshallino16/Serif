import Foundation

/// Wrapper that stores messages alongside pagination state.
struct FolderCache: Codable {
    var messages: [GmailMessage]
    var nextPageToken: String?
}

/// File-based cache for mails, labels, and threads — per account + folder.
final class MailCacheStore {
    static let shared = MailCacheStore()
    private init() {
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    private var baseDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.serif.app/mail-cache", isDirectory: true)
    }

    private func fileURL(accountID: String, folderKey: String) -> URL {
        let accountDir = baseDir.appendingPathComponent(accountID, isDirectory: true)
        try? FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let safe = folderKey.replacingOccurrences(of: "/", with: "_")
        return accountDir.appendingPathComponent("\(safe).json")
    }

    /// Builds a stable cache key from label IDs and optional query.
    static func folderKey(labelIDs: [String], query: String?) -> String {
        let base = labelIDs.sorted().joined(separator: "+")
        if let q = query, !q.isEmpty {
            return "\(base)_q_\(q.hashValue)"
        }
        return base.isEmpty ? "_all" : base
    }

    // MARK: - Messages (FolderCache — with pagination metadata)

    func loadFolderCache(accountID: String, folderKey: String) -> FolderCache {
        let url = fileURL(accountID: accountID, folderKey: folderKey)
        guard let data = try? Data(contentsOf: url) else { return FolderCache(messages: []) }
        // Try new FolderCache format first
        if let cache = try? JSONDecoder().decode(FolderCache.self, from: data) {
            return cache
        }
        // Backward compat: old format was plain [GmailMessage]
        if let messages = try? JSONDecoder().decode([GmailMessage].self, from: data) {
            return FolderCache(messages: messages)
        }
        return FolderCache(messages: [])
    }

    func saveFolderCache(_ cache: FolderCache, accountID: String, folderKey: String) {
        let url = fileURL(accountID: accountID, folderKey: folderKey)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Messages (legacy — used by switchAccount and other non-folder code)

    func load(accountID: String, folderKey: String) -> [GmailMessage] {
        loadFolderCache(accountID: accountID, folderKey: folderKey).messages
    }

    func save(_ messages: [GmailMessage], accountID: String, folderKey: String) {
        let url = fileURL(accountID: accountID, folderKey: folderKey)
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Labels

    func loadLabels(accountID: String) -> [GmailLabel] {
        let url = fileURL(accountID: accountID, folderKey: "_labels")
        guard let data = try? Data(contentsOf: url),
              let labels = try? JSONDecoder().decode([GmailLabel].self, from: data)
        else { return [] }
        return labels
    }

    func saveLabels(_ labels: [GmailLabel], accountID: String) {
        let url = fileURL(accountID: accountID, folderKey: "_labels")
        guard let data = try? JSONEncoder().encode(labels) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Threads (full format, for offline HTML)

    private func threadURL(accountID: String, threadID: String) -> URL {
        let dir = baseDir.appendingPathComponent(accountID, isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(threadID).json")
    }

    func loadThread(accountID: String, threadID: String) -> GmailThread? {
        let url = threadURL(accountID: accountID, threadID: threadID)
        guard let data = try? Data(contentsOf: url),
              let thread = try? JSONDecoder().decode(GmailThread.self, from: data)
        else { return nil }
        return thread
    }

    func saveThread(_ thread: GmailThread, accountID: String) {
        let url = threadURL(accountID: accountID, threadID: thread.id)
        guard let data = try? JSONEncoder().encode(thread) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func deleteAccount(_ accountID: String) {
        let accountDir = baseDir.appendingPathComponent(accountID, isDirectory: true)
        try? FileManager.default.removeItem(at: accountDir)
    }
}
