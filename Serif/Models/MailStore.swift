import Foundation

final class MailStore: ObservableObject {
    @Published var emails: [Email]
    @Published var gmailDrafts: [Email] = []
    @Published var isLoadingGmailDrafts = false

    init(emails: [Email] = []) {
        self.emails = emails
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
            let emails = fetched.compactMap { draft -> Email? in
                guard let message = draft.message else { return nil }
                return Self.makeEmailFromGmailDraft(draft: draft, message: message)
            }
            await MainActor.run { gmailDrafts = emails }
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
            attachments:    message.attachmentParts.map(GmailDataTransformer.makeAttachment),
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
        guard let index = emails.firstIndex(where: { $0.id == id }) else { return }
        emails[index].subject = subject.isEmpty ? "(No subject)" : subject
        emails[index].body = body
        emails[index].preview = body.isEmpty ? "New draft" : String(body.prefix(120))
        emails[index].date = Date()

        // Parse recipients
        if !to.isEmpty {
            emails[index].recipients = to
                .split(separator: ",")
                .map { Contact(name: String($0.trimmingCharacters(in: .whitespaces)), email: String($0.trimmingCharacters(in: .whitespaces))) }
        } else {
            emails[index].recipients = []
        }

        if !cc.isEmpty {
            emails[index].cc = cc
                .split(separator: ",")
                .map { Contact(name: String($0.trimmingCharacters(in: .whitespaces)), email: String($0.trimmingCharacters(in: .whitespaces))) }
        } else {
            emails[index].cc = []
        }
    }

    func deleteDraft(id: UUID) {
        emails.removeAll { $0.id == id }
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
