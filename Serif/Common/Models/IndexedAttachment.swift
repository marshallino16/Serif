import Foundation

struct IndexedAttachment: Identifiable {
    let id: String                  // "{messageId}_{attachmentId}"
    let messageId: String
    let attachmentId: String        // Gmail attachment ID for re-download
    let filename: String
    let mimeType: String?
    let fileType: String            // matches Attachment.FileType raw value
    let size: Int
    let senderEmail: String?
    let senderName: String?
    let emailSubject: String?
    let emailDate: Date?
    let direction: Direction
    let indexedAt: Date?
    let indexingStatus: IndexingStatus
    let extractedText: String?
    let emailBody: String?          // plain-text email body (for FTS search context)
    let accountID: String

    enum Direction: String {
        case received, sent
    }

    enum IndexingStatus: String {
        case pending, indexed, failed, unsupported
    }
}

struct AttachmentSearchResult: Identifiable {
    let id: String
    let attachment: IndexedAttachment
    let score: Double               // 0.0 - 1.0 relevance
    let matchSource: MatchSource

    enum MatchSource {
        case fts          // keyword match
        case semantic     // embedding similarity
        case combined     // both matched
    }
}
