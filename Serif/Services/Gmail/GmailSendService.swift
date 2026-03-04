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
        inlineImages: [InlineImageAttachment] = [],
        attachments: [URL]? = nil,
        accountID: String
    ) async throws -> GmailMessage {
        let raw: String
        let hasAttachments = attachments != nil && !attachments!.isEmpty
        if hasAttachments || !inlineImages.isEmpty {
            raw = buildRawMultipart(
                from: from, to: to, cc: cc, bcc: bcc,
                subject: subject, body: body, isHTML: isHTML,
                referencesHeader: referencesHeader,
                inlineImages: inlineImages,
                attachments: attachments ?? []
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
        if isHTML {
            // multipart/alternative: text/plain + text/html
            let boundary = "BA_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            var lines = [
                "MIME-Version: 1.0",
                "From: \(from)",
                "To: \(to.joined(separator: ", "))",
                "Subject: \(subject)",
                "Content-Type: multipart/alternative; boundary=\"\(boundary)\""
            ]
            if !cc.isEmpty  { lines.append("Cc: \(cc.joined(separator: ", "))") }
            if !bcc.isEmpty { lines.append("Bcc: \(bcc.joined(separator: ", "))") }
            if let ref = referencesHeader {
                lines.append("In-Reply-To: \(ref)")
                lines.append("References: \(ref)")
            }

            var mime = lines.joined(separator: "\r\n") + "\r\n\r\n"
            mime += "--\(boundary)\r\n"
            mime += "Content-Type: text/plain; charset=UTF-8\r\n\r\n"
            mime += body.strippingHTML + "\r\n"
            mime += "--\(boundary)\r\n"
            mime += "Content-Type: text/html; charset=UTF-8\r\n\r\n"
            mime += body + "\r\n"
            mime += "--\(boundary)--"
            return base64URLEncode(mime)
        } else {
            var lines = [
                "MIME-Version: 1.0",
                "From: \(from)",
                "To: \(to.joined(separator: ", "))",
                "Subject: \(subject)",
                "Content-Type: text/plain; charset=UTF-8"
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
    }

    // MARK: - RFC 2822 Builder (multipart/mixed + multipart/related)

    private func buildRawMultipart(
        from: String,
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        body: String,
        isHTML: Bool = true,
        referencesHeader: String? = nil,
        inlineImages: [InlineImageAttachment] = [],
        attachments: [URL]
    ) -> String {
        let boundaryMixed = "BM_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let boundaryRelated = "BR_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let boundaryAlt = "BA_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let hasInline = !inlineImages.isEmpty
        let hasFileAttachments = !attachments.isEmpty

        let topBoundary: String
        let topType: String
        if hasFileAttachments {
            topBoundary = boundaryMixed
            topType = "multipart/mixed"
        } else if hasInline {
            topBoundary = boundaryRelated
            topType = "multipart/related"
        } else {
            topBoundary = boundaryMixed
            topType = "multipart/mixed"
        }

        var lines = [
            "MIME-Version: 1.0",
            "From: \(from)",
            "To: \(to.joined(separator: ", "))",
            "Subject: \(subject)",
            "Content-Type: \(topType); boundary=\"\(topBoundary)\""
        ]
        if !cc.isEmpty  { lines.append("Cc: \(cc.joined(separator: ", "))") }
        if !bcc.isEmpty { lines.append("Bcc: \(bcc.joined(separator: ", "))") }
        if let ref = referencesHeader {
            lines.append("In-Reply-To: \(ref)")
            lines.append("References: \(ref)")
        }

        var mime = lines.joined(separator: "\r\n") + "\r\n\r\n"

        // Helper: builds the body part (multipart/alternative when HTML, or plain text/html part)
        func bodyPart(boundary: String) -> String {
            var part = ""
            if isHTML {
                part += "--\(boundary)\r\n"
                part += "Content-Type: multipart/alternative; boundary=\"\(boundaryAlt)\"\r\n\r\n"
                part += "--\(boundaryAlt)\r\n"
                part += "Content-Type: text/plain; charset=UTF-8\r\n\r\n"
                part += body.strippingHTML + "\r\n"
                part += "--\(boundaryAlt)\r\n"
                part += "Content-Type: text/html; charset=UTF-8\r\n\r\n"
                part += body + "\r\n"
                part += "--\(boundaryAlt)--\r\n"
            } else {
                part += "--\(boundary)\r\n"
                part += "Content-Type: text/plain; charset=UTF-8\r\n\r\n"
                part += body + "\r\n"
            }
            return part
        }

        if hasFileAttachments && hasInline {
            mime += "--\(boundaryMixed)\r\n"
            mime += "Content-Type: multipart/related; boundary=\"\(boundaryRelated)\"\r\n\r\n"
            mime += bodyPart(boundary: boundaryRelated)

            for img in inlineImages {
                let encoded = img.data.base64EncodedString(options: .lineLength76Characters)
                mime += "--\(boundaryRelated)\r\n"
                mime += "Content-Type: \(img.mimeType)\r\n"
                mime += "Content-ID: <\(img.contentID)>\r\n"
                mime += "Content-Disposition: inline; filename=\"\(img.filename)\"\r\n"
                mime += "Content-Transfer-Encoding: base64\r\n\r\n"
                mime += encoded + "\r\n"
            }
            mime += "--\(boundaryRelated)--\r\n"

            for url in attachments {
                guard let data = try? Data(contentsOf: url) else { continue }
                let encoded = data.base64EncodedString(options: .lineLength76Characters)
                mime += "--\(boundaryMixed)\r\n"
                mime += "Content-Type: \(url.mimeType)\r\n"
                mime += "Content-Disposition: attachment; filename=\"\(url.lastPathComponent)\"\r\n"
                mime += "Content-Transfer-Encoding: base64\r\n\r\n"
                mime += encoded + "\r\n"
            }
            mime += "--\(boundaryMixed)--"

        } else if hasInline {
            mime += bodyPart(boundary: boundaryRelated)

            for img in inlineImages {
                let encoded = img.data.base64EncodedString(options: .lineLength76Characters)
                mime += "--\(boundaryRelated)\r\n"
                mime += "Content-Type: \(img.mimeType)\r\n"
                mime += "Content-ID: <\(img.contentID)>\r\n"
                mime += "Content-Disposition: inline; filename=\"\(img.filename)\"\r\n"
                mime += "Content-Transfer-Encoding: base64\r\n\r\n"
                mime += encoded + "\r\n"
            }
            mime += "--\(boundaryRelated)--"

        } else {
            mime += bodyPart(boundary: boundaryMixed)

            for url in attachments {
                guard let data = try? Data(contentsOf: url) else { continue }
                let encoded = data.base64EncodedString(options: .lineLength76Characters)
                mime += "--\(boundaryMixed)\r\n"
                mime += "Content-Type: \(url.mimeType)\r\n"
                mime += "Content-Disposition: attachment; filename=\"\(url.lastPathComponent)\"\r\n"
                mime += "Content-Transfer-Encoding: base64\r\n\r\n"
                mime += encoded + "\r\n"
            }
            mime += "--\(boundaryMixed)--"
        }

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
