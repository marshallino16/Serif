import Foundation

/// Abstracts the Gmail message API surface so services and view models
/// can be tested with mock implementations.
protocol MessageFetching {
    func listMessages(accountID: String, labelIDs: [String], query: String?, pageToken: String?, maxResults: Int) async throws -> GmailMessageListResponse
    func getMessage(id: String, accountID: String, format: String) async throws -> GmailMessage
    func getMessages(ids: [String], accountID: String, format: String) async throws -> [GmailMessage]
    func listHistory(accountID: String, startHistoryId: String, labelId: String?, pageToken: String?, maxResults: Int) async throws -> GmailHistoryListResponse
    func markAsRead(id: String, accountID: String) async throws
    func setStarred(_ starred: Bool, id: String, accountID: String) async throws
    func trashMessage(id: String, accountID: String) async throws
    func archiveMessage(id: String, accountID: String) async throws
    func markAsUnread(id: String, accountID: String) async throws
    func untrashMessage(id: String, accountID: String) async throws
    func deleteMessagePermanently(id: String, accountID: String) async throws
    func spamMessage(id: String, accountID: String) async throws
    @discardableResult
    func modifyLabels(id: String, add: [String], remove: [String], accountID: String) async throws -> GmailMessage
    func getThread(id: String, accountID: String) async throws -> GmailThread
    func getAttachment(messageID: String, attachmentID: String, accountID: String) async throws -> Data
    func emptyTrash(accountID: String) async throws
    func emptySpam(accountID: String) async throws
}

// MARK: - GmailMessageService conformance

extension GmailMessageService: MessageFetching {}
