import Foundation

final class GmailLabelService {
    static let shared = GmailLabelService()
    private init() {}

    func listLabels(accountID: String) async throws -> [GmailLabel] {
        let response: GmailLabelListResponse = try await GmailAPIClient.shared.request(
            path: "/users/me/labels",
            accountID: accountID
        )
        return response.labels
    }
}
