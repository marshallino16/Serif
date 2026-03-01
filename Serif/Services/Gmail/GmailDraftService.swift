import Foundation

/// Fetches drafts from the Gmail Drafts API for display in the Drafts folder.
final class GmailDraftService {
    static let shared = GmailDraftService()
    private init() {}

    private let client = GmailAPIClient.shared

    // MARK: - List Drafts

    /// Lists draft refs for the authenticated user.
    func listDrafts(
        accountID: String,
        pageToken: String? = nil,
        maxResults: Int = 50
    ) async throws -> GmailDraftListResponse {
        var path = "/users/me/drafts?maxResults=\(maxResults)"
        if let token = pageToken { path += "&pageToken=\(token)" }
        return try await client.request(path: path, accountID: accountID)
    }

    // MARK: - Get Draft

    /// Fetches a single draft with its full message payload.
    func getDraft(id: String, accountID: String, format: String = "metadata") async throws -> GmailDraft {
        try await client.request(
            path: "/users/me/drafts/\(id)?format=\(format)",
            accountID: accountID
        )
    }

    // MARK: - Batch fetch

    /// Fetches a batch of draft IDs in groups of 5 to avoid rate limits.
    func getDrafts(ids: [String], accountID: String, format: String = "metadata") async throws -> [GmailDraft] {
        let batchSize = 5
        var all: [GmailDraft] = []
        var offset = 0
        while offset < ids.count {
            let batch = Array(ids[offset..<min(offset + batchSize, ids.count)])
            let batchResult = try await withThrowingTaskGroup(of: GmailDraft.self) { group in
                for id in batch {
                    group.addTask { try await self.getDraft(id: id, accountID: accountID, format: format) }
                }
                var drafts: [GmailDraft] = []
                for try await draft in group { drafts.append(draft) }
                return drafts
            }
            all.append(contentsOf: batchResult)
            offset += batchSize
        }
        // Sort by message date, newest first
        return all.sorted {
            ($0.message?.date ?? .distantPast) > ($1.message?.date ?? .distantPast)
        }
    }
}
