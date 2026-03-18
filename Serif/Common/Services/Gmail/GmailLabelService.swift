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

    func getLabel(id: String, accountID: String) async throws -> GmailLabel {
        return try await GmailAPIClient.shared.request(
            path: "/users/me/labels/\(id)",
            accountID: accountID
        )
    }

    func updateLabel(id: String, newName: String, accountID: String) async throws -> GmailLabel {
        struct UpdateRequest: Encodable { let name: String }
        let body = try JSONEncoder().encode(UpdateRequest(name: newName))
        return try await GmailAPIClient.shared.request(
            path: "/users/me/labels/\(id)",
            method: "PATCH", body: body, contentType: "application/json",
            accountID: accountID
        )
    }

    func deleteLabel(id: String, accountID: String) async throws {
        _ = try await GmailAPIClient.shared.rawRequest(
            path: "/users/me/labels/\(id)",
            method: "DELETE",
            accountID: accountID
        )
    }

    func createLabel(name: String, accountID: String) async throws -> GmailLabel {
        struct CreateRequest: Encodable {
            let name: String
            let labelListVisibility: String
            let messageListVisibility: String
        }
        let body = try JSONEncoder().encode(
            CreateRequest(name: name, labelListVisibility: "labelShow", messageListVisibility: "show")
        )
        return try await GmailAPIClient.shared.request(
            path: "/users/me/labels",
            method: "POST", body: body, contentType: "application/json",
            accountID: accountID
        )
    }
}
