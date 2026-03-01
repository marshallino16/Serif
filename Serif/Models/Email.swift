import Foundation

struct Email: Identifiable, Equatable {
    static func == (lhs: Email, rhs: Email) -> Bool { lhs.id == rhs.id }
    let id: UUID
    var sender: Contact
    var recipients: [Contact]
    var cc: [Contact]
    var subject: String
    var body: String
    var preview: String
    var date: Date
    var isRead: Bool
    var isStarred: Bool
    var hasAttachments: Bool
    var attachments: [Attachment]
    var folder: Folder
    var labels: [EmailLabel]
    var isDraft: Bool
    var isGmailDraft: Bool
    var gmailDraftID: String?
    // Gmail API bridge
    var gmailMessageID: String?
    var gmailThreadID: String?
    var gmailLabelIDs: [String]
    // Mailing-list / unsubscribe
    var isFromMailingList: Bool
    var unsubscribeURL: URL?

    init(
        id: UUID = UUID(),
        sender: Contact,
        recipients: [Contact] = [],
        cc: [Contact] = [],
        subject: String,
        body: String,
        preview: String = "",
        date: Date = Date(),
        isRead: Bool = false,
        isStarred: Bool = false,
        hasAttachments: Bool = false,
        attachments: [Attachment] = [],
        folder: Folder = .inbox,
        labels: [EmailLabel] = [],
        isDraft: Bool = false,
        isGmailDraft: Bool = false,
        gmailDraftID: String? = nil,
        gmailMessageID: String? = nil,
        gmailThreadID: String? = nil,
        gmailLabelIDs: [String] = [],
        isFromMailingList: Bool = false,
        unsubscribeURL: URL? = nil
    ) {
        self.id = id
        self.sender = sender
        self.recipients = recipients
        self.cc = cc
        self.subject = subject
        self.body = body
        self.preview = preview.isEmpty ? String(body.prefix(120)) : preview
        self.date = date
        self.isRead = isRead
        self.isStarred = isStarred
        self.hasAttachments = hasAttachments
        self.attachments = attachments
        self.folder = folder
        self.labels = labels
        self.isDraft = isDraft
        self.isGmailDraft = isGmailDraft
        self.gmailDraftID = gmailDraftID
        self.gmailMessageID = gmailMessageID
        self.gmailThreadID = gmailThreadID
        self.gmailLabelIDs = gmailLabelIDs
        self.isFromMailingList = isFromMailingList
        self.unsubscribeURL = unsubscribeURL
    }
}

struct Contact: Identifiable, Hashable {
    let id: UUID
    let name: String
    let email: String
    let avatarColor: String
    let avatarURL: String?

    init(id: UUID = UUID(), name: String, email: String, avatarColor: String = "#6C5CE7", avatarURL: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.avatarColor = avatarColor
        self.avatarURL = avatarURL
    }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// e.g. "user@example.com" → "example.com"
    var domain: String? {
        guard let atIdx = email.firstIndex(of: "@") else { return nil }
        return String(email[email.index(after: atIdx)...]).lowercased()
    }
}

struct Attachment: Identifiable {
    let id: UUID
    let name: String
    let fileType: FileType
    let size: String

    init(id: UUID = UUID(), name: String, fileType: FileType = .document, size: String = "") {
        self.id = id
        self.name = name
        self.fileType = fileType
        self.size = size
    }

    enum FileType: String, CaseIterable {
        case document = "doc.fill"
        case pdf = "doc.richtext.fill"
        case image = "photo.fill"
        case spreadsheet = "tablecells.fill"
        case archive = "archivebox.fill"
        case presentation = "play.rectangle.fill"
        case code = "chevron.left.forwardslash.chevron.right"

        var label: String {
            switch self {
            case .document: return "Document"
            case .pdf: return "PDF"
            case .image: return "Image"
            case .spreadsheet: return "Spreadsheet"
            case .archive: return "Archive"
            case .presentation: return "Presentation"
            case .code: return "Code"
            }
        }

        static func from(fileExtension ext: String) -> FileType {
            switch ext.lowercased() {
            case "pdf":                                         return .pdf
            case "jpg", "jpeg", "png", "gif", "webp", "heic":  return .image
            case "xls", "xlsx", "csv":                          return .spreadsheet
            case "zip", "gz", "tar", "rar", "7z":               return .archive
            case "ppt", "pptx", "key":                          return .presentation
            case "swift", "py", "js", "ts", "html", "css", "json", "xml": return .code
            default:                                            return .document
            }
        }
    }
}

struct EmailLabel: Identifiable {
    let id: UUID
    let name: String
    let color: String
    let textColor: String

    init(id: UUID = UUID(), name: String, color: String, textColor: String = "#333333") {
        self.id = id
        self.name = name
        self.color = color
        self.textColor = textColor
    }
}

// MARK: - Inbox Categories (Gmail system labels)

enum InboxCategory: String, CaseIterable, Identifiable {
    case all        = "ALL_INBOX"
    case primary    = "CATEGORY_PERSONAL"
    case social     = "CATEGORY_SOCIAL"
    case promotions = "CATEGORY_PROMOTIONS"
    case updates    = "CATEGORY_UPDATES"
    case forums     = "CATEGORY_FORUMS"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:        return "All"
        case .primary:    return "Primary"
        case .social:     return "Social"
        case .promotions: return "Promotions"
        case .updates:    return "Updates"
        case .forums:     return "Forums"
        }
    }

    var icon: String {
        switch self {
        case .all:        return "tray.2"
        case .primary:    return "person.crop.circle"
        case .social:     return "person.2"
        case .promotions: return "tag"
        case .updates:    return "info.circle"
        case .forums:     return "bubble.left.and.bubble.right"
        }
    }

    /// Label IDs to use when querying Gmail API for this category.
    var gmailLabelIDs: [String] {
        switch self {
        case .all: return ["INBOX"]
        default:   return ["INBOX", rawValue]
        }
    }
}

// MARK: - Folder

enum Folder: String, CaseIterable, Identifiable {
    case inbox = "Inbox"
    case starred = "Starred"
    case sent = "Sent"
    case drafts = "Drafts"
    case attachments = "Attachments"
    case subscriptions = "Subscriptions"
    case archive = "Archive"
    case labels = "Labels"
    case spam = "Spam"
    case trash = "Trash"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inbox:         return "tray.fill"
        case .starred:       return "star.fill"
        case .sent:          return "paperplane.fill"
        case .drafts:        return "doc.text.fill"
        case .attachments:   return "paperclip"
        case .subscriptions: return "newspaper.fill"
        case .archive:       return "archivebox.fill"
        case .labels:        return "tag.fill"
        case .spam:          return "exclamationmark.shield.fill"
        case .trash:         return "trash.fill"
        }
    }

    var count: Int { 0 }

    /// Gmail API label ID for this folder (nil = use gmailQuery instead).
    var gmailLabelID: String? {
        switch self {
        case .inbox:       return "INBOX"
        case .starred:     return "STARRED"
        case .sent:        return "SENT"
        case .drafts:      return "DRAFT"
        case .spam:        return "SPAM"
        case .trash:       return "TRASH"
        case .archive, .attachments, .subscriptions, .labels: return nil
        }
    }

    /// Gmail search query for folders that don't map to a single label.
    var gmailQuery: String? {
        switch self {
        case .archive:       return "-in:inbox -in:trash -in:spam -in:drafts"
        case .attachments:   return "has:attachment"
        case .subscriptions, .labels: return nil
        default:                      return nil
        }
    }
}
