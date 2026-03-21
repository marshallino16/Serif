import Foundation

/// Captures all compose state needed to either send the email or restore compose on undo.
struct PendingSend {
    // Fields for restoring compose
    let from: String
    let to: String
    let cc: String
    let bcc: String
    let subject: String
    let bodyHTML: String        // raw editor HTML for restore
    let attachmentURLs: [URL]

    // Fields for actual Gmail API send
    let sanitizedBody: String
    let isHTML: Bool
    let threadID: String?
    let replyToMessageID: String?
    let inlineImages: [InlineImageAttachment]
    let gmailDraftID: String?
    let accountID: String

    func performSend() async {
        let toList = split(to)
        let ccList = split(cc)
        let bccList = split(bcc)
        _ = try? await GmailSendService.shared.send(
            from: from,
            to: toList,
            cc: ccList,
            bcc: bccList,
            subject: subject,
            body: sanitizedBody,
            isHTML: isHTML,
            threadID: threadID,
            referencesHeader: replyToMessageID,
            inlineImages: inlineImages,
            attachments: attachmentURLs.isEmpty ? nil : attachmentURLs,
            accountID: accountID
        )
        if let draftID = gmailDraftID {
            try? await GmailSendService.shared.deleteDraft(draftID: draftID, accountID: accountID)
        }
    }

    private func split(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
