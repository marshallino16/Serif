import SwiftUI

/// Drives the compose / reply / draft editing flow.
@MainActor
final class ComposeViewModel: ObservableObject {
    @Published var to:        String = ""
    @Published var cc:        String = ""
    @Published var subject:   String = ""
    @Published var body:      String = ""
    @Published var isSending  = false
    @Published var isSent     = false
    @Published var error:     String?

    let accountID:   String
    let fromAddress: String
    var gmailDraftID:     String?   // set once we've created a remote draft
    var threadID:         String?   // for replies
    var replyToMessageID: String?   // for In-Reply-To / References headers
    var attachmentURLs:   [URL] = []

    init(accountID: String, fromAddress: String, threadID: String? = nil) {
        self.accountID   = accountID
        self.fromAddress = fromAddress
        self.threadID    = threadID
    }

    // MARK: - Send

    func send() async {
        isSending = true
        error     = nil
        defer { isSending = false }
        do {
            _ = try await GmailSendService.shared.send(
                from:               fromAddress,
                to:                 splitAddresses(to),
                cc:                 splitAddresses(cc),
                subject:            subject,
                body:               body,
                threadID:           threadID,
                referencesHeader:   replyToMessageID,
                attachments:        attachmentURLs.isEmpty ? nil : attachmentURLs,
                accountID:          accountID
            )
            if let draftID = gmailDraftID {
                try? await GmailSendService.shared.deleteDraft(draftID: draftID, accountID: accountID)
            }
            isSent = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Draft

    func saveDraft() async {
        do {
            if let draftID = gmailDraftID {
                let draft = try await GmailSendService.shared.updateDraft(
                    draftID:   draftID,
                    from:      fromAddress,
                    to:        splitAddresses(to),
                    cc:        splitAddresses(cc),
                    subject:   subject,
                    body:      body,
                    accountID: accountID
                )
                gmailDraftID = draft.id
            } else {
                let draft = try await GmailSendService.shared.createDraft(
                    from:      fromAddress,
                    to:        splitAddresses(to),
                    cc:        splitAddresses(cc),
                    subject:   subject,
                    body:      body,
                    accountID: accountID
                )
                gmailDraftID = draft.id
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func discardDraft() async {
        guard let draftID = gmailDraftID else { return }
        try? await GmailSendService.shared.deleteDraft(draftID: draftID, accountID: accountID)
        gmailDraftID = nil
    }

    // MARK: - Helpers

    private func splitAddresses(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var canSend: Bool { !to.isEmpty && !subject.isEmpty }
}
