import Foundation

// MARK: - Message List

struct GmailMessageListResponse: Decodable {
    let messages:            [GmailMessageRef]?
    let nextPageToken:       String?
    let resultSizeEstimate:  Int
}

struct GmailMessageRef: Decodable {
    let id:       String
    let threadId: String
}

// MARK: - Message

struct GmailMessage: Decodable {
    let id:           String
    let threadId:     String
    var labelIds:     [String]?
    let snippet:      String?
    let internalDate: String?
    let payload:      GmailMessagePart?
    let sizeEstimate: Int?
    let historyId:    String?
    let raw:          String?   // base64url-encoded RFC 2822 source (format=raw)
}

struct GmailMessagePart: Decodable {
    let partId:   String?
    let mimeType: String?
    let filename: String?
    let headers:  [GmailHeader]?
    let body:     GmailMessageBody?
    let parts:    [GmailMessagePart]?
}

struct GmailHeader: Decodable {
    let name:  String
    let value: String
}

struct GmailMessageBody: Decodable {
    let attachmentId: String?
    let size:         Int
    let data:         String?   // base64url encoded
}

// MARK: - Thread

struct GmailThread: Decodable {
    let id:        String
    let historyId: String?
    let messages:  [GmailMessage]?
}

struct GmailThreadListResponse: Decodable {
    let threads:            [GmailThreadRef]?
    let nextPageToken:      String?
    let resultSizeEstimate: Int
}

struct GmailThreadRef: Decodable {
    let id:        String
    let snippet:   String?
    let historyId: String?
}

// MARK: - Labels

struct GmailLabelListResponse: Decodable {
    let labels: [GmailLabel]
}

struct GmailLabelColor: Decodable {
    let textColor:       String?
    let backgroundColor: String?
}

struct GmailLabel: Decodable, Identifiable {
    let id:              String
    let name:            String
    let type:            String?
    let messagesTotal:   Int?
    let messagesUnread:  Int?
    let threadsTotal:    Int?
    let threadsUnread:   Int?
    let color:           GmailLabelColor?
}

// MARK: - GmailLabel Helpers

extension GmailLabel {
    static let systemLabelIDs: Set<String> = [
        "INBOX", "UNREAD", "STARRED", "IMPORTANT",
        "SENT", "DRAFT", "TRASH", "SPAM",
        "CATEGORY_PERSONAL", "CATEGORY_SOCIAL",
        "CATEGORY_PROMOTIONS", "CATEGORY_UPDATES", "CATEGORY_FORUMS"
    ]

    var isSystemLabel: Bool { GmailLabel.systemLabelIDs.contains(id) }

    /// Last path component of the name (e.g. "work/projects" → "projects").
    var displayName: String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    // Stable palette used for labels that have no API colour set.
    private static let colorPalette: [(bg: String, text: String)] = [
        ("#e8f0fe", "#1967d2"),
        ("#fce8e6", "#c5221f"),
        ("#e6f4ea", "#137333"),
        ("#fef7e0", "#b06000"),
        ("#f3e8fd", "#6200ea"),
        ("#fde7f3", "#ad1457"),
        ("#fff3e0", "#e65100"),
        ("#e3f2fd", "#0277bd"),
    ]

    var resolvedBgColor: String {
        if let bg = color?.backgroundColor, !bg.isEmpty { return bg }
        return GmailLabel.colorPalette[abs(id.hashValue) % GmailLabel.colorPalette.count].bg
    }

    var resolvedTextColor: String {
        if let text = color?.textColor, !text.isEmpty { return text }
        return GmailLabel.colorPalette[abs(id.hashValue) % GmailLabel.colorPalette.count].text
    }
}

// MARK: - Profile

struct GmailProfile: Decodable {
    let emailAddress:  String
    let messagesTotal: Int
    let threadsTotal:  Int
    let historyId:     String
}

// MARK: - Send As / Signature

struct GmailSendAsListResponse: Decodable {
    let sendAs: [GmailSendAs]
}

struct GmailSendAs: Decodable {
    let sendAsEmail: String
    let displayName: String?
    let signature:   String?
    let isDefault:   Bool?
    let isPrimary:   Bool?
}


// MARK: - Attachment

struct GmailAttachmentResponse: Decodable {
    let size: Int
    let data: String    // base64url encoded
}

// MARK: - Draft

struct GmailDraft: Decodable {
    let id:      String
    let message: GmailMessage?
}

struct GmailDraftListResponse: Decodable {
    let drafts:             [GmailDraftRef]?
    let nextPageToken:      String?
    let resultSizeEstimate: Int
}

struct GmailDraftRef: Decodable {
    let id:      String
    let message: GmailMessageRef?
}

// MARK: - GmailMessage Helpers

extension GmailMessage {
    func header(named name: String) -> String? {
        payload?.headers?.first(where: { $0.name.lowercased() == name.lowercased() })?.value
    }

    var subject:   String { header(named: "Subject") ?? "(no subject)" }
    var from:      String { header(named: "From")    ?? "" }
    var to:        String { header(named: "To")      ?? "" }
    var cc:        String { header(named: "Cc")      ?? "" }
    var replyTo:   String { header(named: "Reply-To") ?? from }
    var messageID: String { header(named: "Message-ID") ?? "" }
    var inReplyTo: String { header(named: "In-Reply-To") ?? "" }

    var date: Date? {
        guard let ms = internalDate, let msInt = Int64(ms) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(msInt) / 1000)
    }

    var isUnread:  Bool { labelIds?.contains("UNREAD")   ?? false }
    var isStarred: Bool { labelIds?.contains("STARRED")  ?? false }
    var isDraft:   Bool { labelIds?.contains("DRAFT")    ?? false }

    /// True when the message was sent by a mailing list (List-Unsubscribe or List-Id header present).
    var isFromMailingList: Bool {
        header(named: "List-Unsubscribe") != nil || header(named: "List-Id") != nil
    }

    /// Parses the List-Unsubscribe header and returns the best URL (HTTPS preferred over mailto).
    var unsubscribeURL: URL? {
        guard let raw = header(named: "List-Unsubscribe") else { return nil }
        var https: URL? = nil
        var mailto: URL? = nil
        var pos = raw.startIndex
        while let open = raw[pos...].firstIndex(of: "<") {
            let after = raw.index(after: open)
            if let close = raw[after...].firstIndex(of: ">") {
                let entry = String(raw[after..<close]).trimmingCharacters(in: .whitespaces)
                if entry.hasPrefix("http"), https == nil  { https = URL(string: entry) }
                if entry.hasPrefix("mailto"), mailto == nil { mailto = URL(string: entry) }
                pos = raw.index(after: close)
            } else { break }
        }
        return https ?? mailto
    }

    /// True when RFC 8058 one-click unsubscribe via POST is supported.
    var supportsOneClickUnsubscribe: Bool {
        header(named: "List-Unsubscribe-Post") != nil
    }

    /// Recursively extracts text/html body.
    var htmlBody:  String? { extractBody(mimeType: "text/html",  from: payload) }
    var plainBody: String? { extractBody(mimeType: "text/plain", from: payload) }

    var body: String { htmlBody ?? plainBody ?? snippet ?? "" }

    /// Parts that are actual file attachments.
    var attachmentParts: [GmailMessagePart] { collectAttachments(from: payload) }

    /// Decodes the raw RFC 2822 source from base64url.
    var rawSource: String? {
        guard let raw = raw else { return nil }
        return decodeBase64URL(raw)
    }

    // MARK: Private helpers

    private func extractBody(mimeType: String, from part: GmailMessagePart?) -> String? {
        guard let part = part else { return nil }
        if part.mimeType == mimeType, let data = part.body?.data {
            return decodeBase64URL(data)
        }
        for sub in part.parts ?? [] {
            if let body = extractBody(mimeType: mimeType, from: sub) { return body }
        }
        return nil
    }

    private func decodeBase64URL(_ string: String) -> String? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func collectAttachments(from part: GmailMessagePart?) -> [GmailMessagePart] {
        guard let part = part else { return [] }
        var result: [GmailMessagePart] = []
        if let filename = part.filename, !filename.isEmpty, part.body?.attachmentId != nil {
            result.append(part)
        }
        for sub in part.parts ?? [] { result += collectAttachments(from: sub) }
        return result
    }
}
