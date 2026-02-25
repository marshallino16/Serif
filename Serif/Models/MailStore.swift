import Foundation

final class MailStore: ObservableObject {
    @Published var emails: [Email]

    init(emails: [Email] = []) {
        self.emails = emails
    }

    func emails(for folder: Folder) -> [Email] {
        emails.filter { $0.folder == folder }
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
