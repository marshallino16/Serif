import Foundation

final class GmailMessageService {
    static let shared = GmailMessageService()
    private init() {}

    private let client = GmailAPIClient.shared

    // MARK: - List

    /// Lists message refs for a given label and optional search query.
    func listMessages(
        accountID: String,
        labelIDs: [String] = [GmailSystemLabel.inbox],
        query: String? = nil,
        pageToken: String? = nil,
        maxResults: Int = 50
    ) async throws -> GmailMessageListResponse {
        var path = "/users/me/messages?maxResults=\(maxResults)"
        for label in labelIDs { path += "&labelIds=\(label)" }
        if let q = query, !q.isEmpty {
            path += "&q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)"
        }
        if let token = pageToken { path += "&pageToken=\(token)" }
        return try await client.request(path: path, accountID: accountID)
    }

    // MARK: - Fetch single message

    /// Fetches a single message. Use format "full" for detail view, "metadata" for list.
    func getMessage(id: String, accountID: String, format: String = "full") async throws -> GmailMessage {
        try await client.request(path: "/users/me/messages/\(id)?format=\(format)", accountID: accountID)
    }

    /// Fetches the raw RFC 2822 source of a message.
    func getRawMessage(id: String, accountID: String) async throws -> GmailMessage {
        try await getMessage(id: id, accountID: accountID, format: "raw")
    }

    /// Fetches a batch of message IDs in groups of 5 to avoid "too many concurrent requests".
    func getMessages(ids: [String], accountID: String, format: String = "metadata") async throws -> [GmailMessage] {
        let batchSize = 5
        var all: [GmailMessage] = []
        var offset = 0
        while offset < ids.count {
            let batch = Array(ids[offset..<min(offset + batchSize, ids.count)])
            let batchResult = try await withThrowingTaskGroup(of: GmailMessage.self) { group in
                for id in batch {
                    group.addTask { try await self.getMessage(id: id, accountID: accountID, format: format) }
                }
                var msgs: [GmailMessage] = []
                for try await msg in group { msgs.append(msg) }
                return msgs
            }
            all.append(contentsOf: batchResult)
            offset += batchSize
        }
        return all.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    // MARK: - Threads

    func getThread(id: String, accountID: String) async throws -> GmailThread {
        try await client.request(path: "/users/me/threads/\(id)?format=full", accountID: accountID)
    }

    // MARK: - History

    /// Fetches history records since the given historyId.
    /// Pass labelId to filter only changes relevant to a specific label.
    func listHistory(
        accountID: String,
        startHistoryId: String,
        labelId: String? = nil,
        pageToken: String? = nil,
        maxResults: Int = 500
    ) async throws -> GmailHistoryListResponse {
        var path = "/users/me/history?startHistoryId=\(startHistoryId)&maxResults=\(maxResults)"
        path += "&historyTypes=messageAdded&historyTypes=messageDeleted"
        path += "&historyTypes=labelAdded&historyTypes=labelRemoved"
        if let labelId { path += "&labelId=\(labelId)" }
        if let token = pageToken { path += "&pageToken=\(token)" }
        return try await client.request(path: path, accountID: accountID)
    }

    // MARK: - Mutations

    func markAsRead(id: String, accountID: String) async throws {
        try await modifyLabels(id: id, add: [], remove: [GmailSystemLabel.unread], accountID: accountID)
    }

    func setStarred(_ starred: Bool, id: String, accountID: String) async throws {
        if starred {
            try await modifyLabels(id: id, add: [GmailSystemLabel.starred], remove: [], accountID: accountID)
        } else {
            try await modifyLabels(id: id, add: [], remove: [GmailSystemLabel.starred], accountID: accountID)
        }
    }

    func trashMessage(id: String, accountID: String) async throws {
        let _: GmailMessage = try await client.request(
            path: "/users/me/messages/\(id)/trash",
            method: "POST",
            accountID: accountID
        )
    }

    func archiveMessage(id: String, accountID: String) async throws {
        try await modifyLabels(id: id, add: [], remove: [GmailSystemLabel.inbox], accountID: accountID)
    }

    func markAsUnread(id: String, accountID: String) async throws {
        try await modifyLabels(id: id, add: [GmailSystemLabel.unread], remove: [], accountID: accountID)
    }

    func untrashMessage(id: String, accountID: String) async throws {
        let _: GmailMessage = try await client.request(
            path: "/users/me/messages/\(id)/untrash",
            method: "POST",
            accountID: accountID
        )
    }

    func deleteMessagePermanently(id: String, accountID: String) async throws {
        _ = try await client.rawRequest(
            path: "/users/me/messages/\(id)",
            method: "DELETE",
            accountID: accountID
        )
    }

    func spamMessage(id: String, accountID: String) async throws {
        try await modifyLabels(id: id, add: [GmailSystemLabel.spam], remove: [GmailSystemLabel.inbox], accountID: accountID)
    }

    @discardableResult
    func modifyLabels(id: String, add: [String], remove: [String], accountID: String) async throws -> GmailMessage {
        struct ModifyRequest: Encodable { let addLabelIds: [String]; let removeLabelIds: [String] }
        let body = try JSONEncoder().encode(ModifyRequest(addLabelIds: add, removeLabelIds: remove))
        return try await client.request(
            path: "/users/me/messages/\(id)/modify",
            method: "POST", body: body, contentType: "application/json",
            accountID: accountID
        )
    }

    /// Permanently deletes all messages in Trash.
    /// Continues through all batches even if some fail, then reports partial failure.
    func emptyTrash(accountID: String) async throws {
        try await emptyFolder(labelID: GmailSystemLabel.trash, accountID: accountID)
    }

    /// Permanently deletes all messages in Spam.
    /// Continues through all batches even if some fail, then reports partial failure.
    func emptySpam(accountID: String) async throws {
        try await emptyFolder(labelID: GmailSystemLabel.spam, accountID: accountID)
    }

    private func emptyFolder(labelID: String, accountID: String) async throws {
        var pageToken: String? = nil
        var allIDs: [String] = []
        repeat {
            let response = try await listMessages(
                accountID: accountID,
                labelIDs: [labelID],
                pageToken: pageToken,
                maxResults: 100
            )
            allIDs.append(contentsOf: response.messages?.map(\.id) ?? [])
            pageToken = response.nextPageToken
        } while pageToken != nil

        guard !allIDs.isEmpty else { return }

        // Batch delete in groups of 100 (API limit), accumulating failures
        var failedIDs: [String] = []
        for batch in stride(from: 0, to: allIDs.count, by: 100) {
            let ids = Array(allIDs[batch..<min(batch + 100, allIDs.count)])
            do {
                struct BatchDeleteRequest: Encodable { let ids: [String] }
                let body = try JSONEncoder().encode(BatchDeleteRequest(ids: ids))
                _ = try await client.rawRequest(
                    path: "/users/me/messages/batchDelete",
                    method: "POST", body: body, contentType: "application/json",
                    accountID: accountID
                )
            } catch {
                failedIDs.append(contentsOf: ids)
            }
        }
        if !failedIDs.isEmpty {
            throw GmailAPIError.partialFailure(failedCount: failedIDs.count)
        }
    }

    // MARK: - Attachments

    /// Downloads raw attachment data by attachment ID.
    func getAttachment(messageID: String, attachmentID: String, accountID: String) async throws -> Data {
        let response: GmailAttachmentResponse = try await client.request(
            path: "/users/me/messages/\(messageID)/attachments/\(attachmentID)",
            accountID: accountID
        )
        guard let data = Data(base64URLEncoded: response.data) else {
            throw GmailAPIError.decodingError(URLError(.badServerResponse))
        }
        return data
    }
}
