import SwiftUI

struct DetailPaneView: View {
    let selectedEmail: Email?
    let selectedEmailIDs: Set<String>
    let selectedFolder: Folder
    let displayedEmails: [Email]

    let actionCoordinator: EmailActionCoordinator
    let mailboxViewModel: MailboxViewModel
    let mailStore: MailStore
    let accountID: String
    let fromAddress: String

    let composeMode: ComposeMode
    let signatureForNew: String
    let signatureForReply: String

    let panelCoordinator: PanelCoordinator

    let onSelectNext: (Email?) -> Void
    let onClearSelection: () -> Void
    let onDeselectAll: () -> Void
    let onStartCompose: (ComposeMode) -> Void
    let onDiscardDraft: (UUID) -> Void

    @Environment(\.theme) private var theme

    private var isMultiSelect: Bool { selectedEmailIDs.count > 1 }

    private var isEditingDraft: Bool {
        guard let email = selectedEmail else { return false }
        return email.isDraft && !email.isGmailDraft
    }

    private var selectedEmails: [Email] {
        displayedEmails.filter { selectedEmailIDs.contains($0.id.uuidString) }
    }

    var body: some View {
        Group {
            if isMultiSelect {
                bulkActionView
            } else if isEditingDraft, let draftId = selectedEmail?.id {
                composeView(draftId: draftId)
            } else if let email = selectedEmail {
                emailDetailView(email: email)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 400)
    }

    // MARK: - Bulk Actions

    private var bulkActionView: some View {
        BulkActionBarView(
            count: selectedEmailIDs.count,
            selectedFolder: selectedFolder,
            onArchive:     { actionCoordinator.bulkArchive(selectedEmails, onClear: onClearSelection) },
            onDelete:      { actionCoordinator.bulkDelete(selectedEmails, onClear: onClearSelection) },
            onMarkUnread:  { actionCoordinator.bulkMarkUnread(selectedEmails, onClear: onDeselectAll) },
            onMarkRead:    { actionCoordinator.bulkMarkRead(selectedEmails, onClear: onDeselectAll) },
            onToggleStar:  { for e in selectedEmails { actionCoordinator.toggleStarEmail(e) } },
            onMoveToInbox: { actionCoordinator.bulkMoveToInbox(selectedEmails, selectedFolder: selectedFolder, onClear: onClearSelection) },
            onDeselectAll: onDeselectAll
        )
    }

    // MARK: - Compose

    private func composeView(draftId: UUID) -> some View {
        ComposeView(
            mailStore: mailStore,
            draftId: draftId,
            accountID: accountID,
            fromAddress: fromAddress,
            mode: composeMode,
            sendAsAliases: mailboxViewModel.sendAsAliases,
            signatureForNew: signatureForNew,
            signatureForReply: signatureForReply,
            contacts: ContactStore.shared.contacts(for: accountID),
            onDiscard: { onDiscardDraft(draftId) }
        )
        .id(draftId)
    }

    // MARK: - Email Detail

    private func emailDetailView(email: Email) -> some View {
        EmailDetailView(
            email: email,
            accountID: accountID,
            onArchive: selectedFolder == .archive ? nil : { actionCoordinator.archiveEmail(email, selectNext: onSelectNext) },
            onDelete: selectedFolder == .trash ? nil : { actionCoordinator.deleteEmail(email, selectNext: onSelectNext) },
            onMoveToInbox: selectedFolder == .archive || selectedFolder == .trash
                ? { actionCoordinator.moveToInboxEmail(email, selectedFolder: selectedFolder, selectNext: onSelectNext) } : nil,
            onDeletePermanently: selectedFolder == .trash
                ? { actionCoordinator.deletePermanentlyEmail(email, selectNext: onSelectNext) } : nil,
            onMarkNotSpam: selectedFolder == .spam
                ? { actionCoordinator.markNotSpamEmail(email, selectNext: onSelectNext) } : nil,
            onToggleStar: { isCurrentlyStarred in
                guard let msgID = email.gmailMessageID else { return }
                Task { await mailboxViewModel.toggleStar(msgID, isStarred: isCurrentlyStarred) }
            },
            onMarkUnread: { actionCoordinator.markUnreadEmail(email) },
            allLabels: mailboxViewModel.labels,
            onAddLabel: { labelID in
                guard let msgID = email.gmailMessageID else { return }
                Task { await mailboxViewModel.addLabel(labelID, to: msgID) }
            },
            onRemoveLabel: { labelID in
                guard let msgID = email.gmailMessageID else { return }
                Task { await mailboxViewModel.removeLabel(labelID, from: msgID) }
            },
            onReply: onStartCompose,
            onReplyAll: onStartCompose,
            onForward: onStartCompose,
            onCreateAndAddLabel: { name, completion in
                guard let msgID = email.gmailMessageID else { completion(nil); return }
                Task {
                    let labelID = await mailboxViewModel.createAndAddLabel(name: name, to: msgID)
                    completion(labelID)
                }
            },
            onPreviewAttachment: { data, name, fileType in
                panelCoordinator.previewAttachment(data: data, name: name, fileType: fileType)
            },
            onShowOriginal: { vm in panelCoordinator.showOriginalMessage(from: vm) },
            onDownloadMessage: { vm in panelCoordinator.downloadMessage(from: vm) },
            onUnsubscribe: { url, oneClick, msgID in
                await UnsubscribeService.shared.unsubscribe(url: url, oneClick: oneClick, messageID: msgID)
            },
            onPrint: { msg, email in
                EmailPrintService.shared.printEmail(message: msg, email: email)
            },
            checkUnsubscribed: { msgID in
                UnsubscribeService.shared.isUnsubscribed(messageID: msgID)
            },
            extractBodyUnsubscribeURL: { html in
                UnsubscribeService.extractBodyUnsubscribeURL(from: html)
            }
        )
        .id(email.id)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.open")
                .font(.system(size: 40))
                .foregroundColor(theme.textTertiary)
            Text("Select an email to read")
                .font(.system(size: 14))
                .foregroundColor(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.detailBackground)
    }
}
