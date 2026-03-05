import Foundation

final class MailStore: ObservableObject {
    @Published var emails: [Email]
    @Published var gmailDrafts: [Email] = []
    @Published var isLoadingGmailDrafts = false

    /// In-progress quick reply drafts, keyed by Gmail thread ID.
    /// Only stores the link — content is always fetched fresh from Gmail.
    struct ReplyDraftInfo: Codable {
        let gmailDraftID: String
        let preview: String  // short plain text for collapsed placeholder
    }
    var replyDrafts: [String: ReplyDraftInfo] = [:]

    private static let replyDraftsKey = "replyDrafts"

    init(emails: [Email] = []) {
        self.emails = emails
        loadReplyDrafts()
    }

    func saveReplyDrafts() {
        guard let data = try? JSONEncoder().encode(replyDrafts) else { return }
        UserDefaults.standard.set(data, forKey: Self.replyDraftsKey)
    }

    private func loadReplyDrafts() {
        guard let data = UserDefaults.standard.data(forKey: Self.replyDraftsKey),
              let decoded = try? JSONDecoder().decode([String: ReplyDraftInfo].self, from: data) else { return }
        replyDrafts = decoded
    }

    func emails(for folder: Folder) -> [Email] {
        if folder == .drafts {
            // Merge local drafts (newest first) + Gmail drafts, sorted by date
            let localDrafts = emails.filter { $0.folder == .drafts }
            return (localDrafts + gmailDrafts).sorted { $0.date > $1.date }
        }
        return emails.filter { $0.folder == folder }
    }

    // MARK: - Gmail Drafts Sync

    func syncGmailDrafts(accountID: String) async {
        guard !accountID.isEmpty else { return }
        await MainActor.run { isLoadingGmailDrafts = true }
        defer { Task { @MainActor in isLoadingGmailDrafts = false } }
        do {
            let listResponse = try await GmailDraftService.shared.listDrafts(accountID: accountID)
            let draftRefs = listResponse.drafts ?? []
            guard !draftRefs.isEmpty else {
                await MainActor.run { gmailDrafts = [] }
                return
            }
            let draftIDs = draftRefs.map(\.id)
            let fetched = try await GmailDraftService.shared.getDrafts(
                ids: draftIDs, accountID: accountID, format: "full"
            )
            var emails: [Email] = []
            for draft in fetched {
                guard let message = draft.message else { continue }
                var email = Self.makeEmailFromGmailDraft(draft: draft, message: message)

                // Resolve cid: → data: for inline images so they display in the editor
                let inlineParts = message.inlineParts
                if !inlineParts.isEmpty && email.body.contains("cid:") {
                    var body = email.body
                    for part in inlineParts {
                        guard let cid = part.contentID,
                              let mime = part.mimeType else { continue }

                        let imageBase64: String?
                        if let embedded = part.body?.data {
                            // Data embedded in "full" response — convert base64url → base64
                            var b64 = embedded
                                .replacingOccurrences(of: "-", with: "+")
                                .replacingOccurrences(of: "_", with: "/")
                            while b64.count % 4 != 0 { b64 += "=" }
                            imageBase64 = b64
                        } else if let attID = part.body?.attachmentId {
                            // Large image — fetch via attachment API
                            if let data = try? await GmailMessageService.shared.getAttachment(
                                messageID: message.id, attachmentID: attID, accountID: accountID
                            ) {
                                imageBase64 = data.base64EncodedString()
                            } else {
                                imageBase64 = nil
                            }
                        } else {
                            imageBase64 = nil
                        }

                        if let b64 = imageBase64 {
                            let dataURI = "data:\(mime);base64,\(b64)"
                            body = body.replacingOccurrences(
                                of: "src=\"cid:\(cid)\"",
                                with: "src=\"\(dataURI)\" data-cid=\"\(cid)\""
                            )
                        }
                    }
                    email.body = body
                }
                emails.append(email)
            }
            await MainActor.run {
                gmailDrafts = emails
                // Remove local drafts that now exist as Gmail drafts to avoid duplicates
                let syncedGmailIDs = Set(emails.compactMap(\.gmailDraftID))
                self.emails.removeAll { email in
                    email.folder == .drafts && email.isDraft
                        && email.gmailDraftID != nil
                        && syncedGmailIDs.contains(email.gmailDraftID!)
                }
            }
        } catch {
            // Silently fail — keep existing cached drafts if any
            print("[GmailDraftSync] Error: \(error.localizedDescription)")
        }
    }

    /// Converts a Gmail draft + message into a read-only Email for display.
    private static func makeEmailFromGmailDraft(draft: GmailDraft, message: GmailMessage) -> Email {
        let msgLabelIDs = message.labelIds ?? []
        return Email(
            id:             GmailDataTransformer.deterministicUUID(from: draft.id),
            sender:         GmailDataTransformer.parseContact(message.from),
            recipients:     GmailDataTransformer.parseContacts(message.to),
            cc:             GmailDataTransformer.parseContacts(message.cc),
            subject:        message.subject,
            body:           message.body,
            preview:        message.snippet ?? "",
            date:           message.date ?? Date(),
            isRead:         true,
            isStarred:      message.isStarred,
            hasAttachments: !message.attachmentParts.isEmpty,
            attachments:    message.attachmentParts.map { GmailDataTransformer.makeAttachment(from: $0, messageId: message.id) },
            folder:         .drafts,
            labels:         [],
            isDraft:             true,
            isGmailDraft:        true,
            gmailDraftID:        draft.id,
            gmailMessageID:      message.id,
            gmailThreadID:       message.threadId,
            gmailLabelIDs:       msgLabelIDs,
            isFromMailingList:   false,
            unsubscribeURL:      nil
        )
    }

    // MARK: - Drafts

    @discardableResult
    func createDraft() -> Email {
        var draft = Email(
            sender: Contact(name: "", email: ""),
            subject: "",
            body: "",
            folder: .drafts,
            isDraft: true
        )
        draft.preview = "New draft"
        emails.insert(draft, at: 0)
        return draft
    }

    func updateDraft(id: UUID, subject: String, body: String, to: String, cc: String) {
        let parseContacts: (String) -> [Contact] = { raw in
            raw.split(separator: ",")
                .map { Contact(name: String($0.trimmingCharacters(in: .whitespaces)), email: String($0.trimmingCharacters(in: .whitespaces))) }
        }

        // Try local drafts first, then Gmail drafts
        if let index = emails.firstIndex(where: { $0.id == id }) {
            emails[index].subject    = subject.isEmpty ? "(No subject)" : subject
            emails[index].body       = body
            emails[index].preview    = body.isEmpty ? "New draft" : String(body.strippingHTML.prefix(120))
            emails[index].date       = Date()
            emails[index].recipients = to.isEmpty ? [] : parseContacts(to)
            emails[index].cc         = cc.isEmpty ? [] : parseContacts(cc)
        } else if let index = gmailDrafts.firstIndex(where: { $0.id == id }) {
            gmailDrafts[index].subject    = subject.isEmpty ? "(No subject)" : subject
            gmailDrafts[index].body       = body
            gmailDrafts[index].preview    = body.isEmpty ? "New draft" : String(body.strippingHTML.prefix(120))
            gmailDrafts[index].date       = Date()
            gmailDrafts[index].recipients = to.isEmpty ? [] : parseContacts(to)
            gmailDrafts[index].cc         = cc.isEmpty ? [] : parseContacts(cc)
        }
    }

    /// Persists the Gmail draft ID on the local Email so it survives ComposeView destruction.
    func setGmailDraftID(_ gid: String, for id: UUID) {
        if let index = emails.firstIndex(where: { $0.id == id }) {
            emails[index].gmailDraftID = gid
        }
    }

    func deleteDraft(id: UUID) {
        emails.removeAll { $0.id == id }
        gmailDrafts.removeAll { $0.id == id }
    }

    // MARK: - Attachments

    func allAttachmentItems() -> [AttachmentItem] {
        emails.flatMap { email in
            email.attachments.map { attachment in
                AttachmentItem(
                    attachment: attachment,
                    emailId: email.id,
                    emailSubject: email.subject,
                    senderName: email.sender.name,
                    senderColor: email.sender.avatarColor,
                    date: email.date,
                    direction: email.folder == .sent ? .sent : .received
                )
            }
        }
        .sorted { $0.date > $1.date }
    }
}

// MARK: - Attachment Item (attachment with email context)

struct AttachmentItem: Identifiable {
    let id: UUID
    let attachment: Attachment
    let emailId: UUID
    let emailSubject: String
    let senderName: String
    let senderColor: String
    let date: Date
    let direction: Direction

    enum Direction: String, CaseIterable {
        case received = "Received"
        case sent = "Sent"
    }

    init(
        attachment: Attachment,
        emailId: UUID,
        emailSubject: String,
        senderName: String,
        senderColor: String,
        date: Date,
        direction: Direction
    ) {
        self.id = attachment.id
        self.attachment = attachment
        self.emailId = emailId
        self.emailSubject = emailSubject
        self.senderName = senderName
        self.senderColor = senderColor
        self.date = date
        self.direction = direction
    }

}
