import Foundation

final class GmailSendService {
    static let shared = GmailSendService()
    private init() {}

    // MARK: - Send

    func send(
        from: String,
        to: [String],
        cc: [String] = [],
        bcc: [String] = [],
        subject: String,
        body: String,
        isHTML: Bool = false,
        threadID: String? = nil,
        referencesHeader: String? = nil,
        attachments: [URL]? = nil,
        accountID: String
    ) async throws -> GmailMessage {
        let raw: String
        if let attachments = attachments, !attachments.isEmpty {
            raw = buildRawMultipart(
                from: from, to: to, cc: cc, bcc: bcc,
                subject: subject, body: body,
                referencesHeader: referencesHeader,
                attachments: attachments
            )
        } else {
            raw = buildRaw(
                from: from, to: to, cc: cc, bcc: bcc,
                subject: subject, body: body, isHTML: isHTML,
                referencesHeader: referencesHeader
            )
        }
        var payload: [String: Any] = ["raw": raw]
        if let threadID { payload["threadId"] = threadID }
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        return try await GmailAPIClient.shared.request(
            path: "/users/me/messages/send",
            method: "POST", body: encoded, contentType: "application/json",
            accountID: accountID
        )
    }

    // MARK: - Drafts

    func createDraft(
        from: String,
        to: [String],
        cc: [String] = [],
        subject: String,
        body: String,
        isHTML: Bool = false,
        accountID: String
    ) async throws -> GmailDraft {
        let raw = buildRaw(from: from, to: to, cc: cc, bcc: [], subject: subject, body: body, isHTML: isHTML)
        let payload: [String: Any] = ["message": ["raw": raw]]
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        return try await GmailAPIClient.shared.request(
            path: "/users/me/drafts",
            method: "POST", body: encoded, contentType: "application/json",
            accountID: accountID
        )
    }

    func updateDraft(
        draftID: String,
        from: String,
        to: [String],
        cc: [String] = [],
        subject: String,
        body: String,
        isHTML: Bool = false,
        accountID: String
    ) async throws -> GmailDraft {
        let raw = buildRaw(from: from, to: to, cc: cc, bcc: [], subject: subject, body: body, isHTML: isHTML)
        let payload: [String: Any] = ["message": ["raw": raw]]
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        return try await GmailAPIClient.shared.request(
            path: "/users/me/drafts/\(draftID)",
            method: "PUT", body: encoded, contentType: "application/json",
            accountID: accountID
        )
    }

    func deleteDraft(draftID: String, accountID: String) async throws {
        _ = try await GmailAPIClient.shared.rawRequest(
            path: "/users/me/drafts/\(draftID)",
            method: "DELETE",
            accountID: accountID
        )
    }

    // MARK: - RFC 2822 Builder (plain / HTML)

    private func buildRaw(
        from: String,
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        body: String,
        isHTML: Bool,
        referencesHeader: String? = nil
    ) -> String {
        var lines = [
            "MIME-Version: 1.0",
            "From: \(from)",
            "To: \(to.joined(separator: ", "))",
            "Subject: \(subject)",
            "Content-Type: \(isHTML ? "text/html" : "text/plain"); charset=UTF-8"
        ]
        if !cc.isEmpty  { lines.append("Cc: \(cc.joined(separator: ", "))") }
        if !bcc.isEmpty { lines.append("Bcc: \(bcc.joined(separator: ", "))") }
        if let ref = referencesHeader {
            lines.append("In-Reply-To: \(ref)")
            lines.append("References: \(ref)")
        }

        let raw = lines.joined(separator: "\r\n") + "\r\n\r\n" + body
        return base64URLEncode(raw)
    }

    // MARK: - RFC 2822 Builder (multipart/mixed with attachments)

    private func buildRawMultipart(
        from: String,
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        body: String,
        referencesHeader: String? = nil,
        attachments: [URL]
    ) -> String {
        let boundary = "Boundary_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"

        var lines = [
            "MIME-Version: 1.0",
            "From: \(from)",
            "To: \(to.joined(separator: ", "))",
            "Subject: \(subject)",
            "Content-Type: multipart/mixed; boundary=\"\(boundary)\""
        ]
        if !cc.isEmpty  { lines.append("Cc: \(cc.joined(separator: ", "))") }
        if !bcc.isEmpty { lines.append("Bcc: \(bcc.joined(separator: ", "))") }
        if let ref = referencesHeader {
            lines.append("In-Reply-To: \(ref)")
            lines.append("References: \(ref)")
        }

        var mime = lines.joined(separator: "\r\n") + "\r\n\r\n"

        // Body part
        mime += "--\(boundary)\r\n"
        mime += "Content-Type: text/html; charset=UTF-8\r\n\r\n"
        mime += body + "\r\n"

        // Attachment parts
        for url in attachments {
            guard let data = try? Data(contentsOf: url) else { continue }
            let filename = url.lastPathComponent
            let mimeType = url.mimeType
            let encoded = data.base64EncodedString(options: .lineLength76Characters)

            mime += "--\(boundary)\r\n"
            mime += "Content-Type: \(mimeType)\r\n"
            mime += "Content-Disposition: attachment; filename=\"\(filename)\"\r\n"
            mime += "Content-Transfer-Encoding: base64\r\n\r\n"
            mime += encoded + "\r\n"
        }

        mime += "--\(boundary)--"
        return base64URLEncode(mime)
    }

    // MARK: - Helpers

    private func base64URLEncode(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
