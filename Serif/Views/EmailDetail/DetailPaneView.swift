import SwiftUI

struct DetailPaneView: View {
    let selectedEmail: Email?
    let selectedEmailIDs: Set<String>
    let selectedFolder: Folder
    let displayedEmails: [Email]

    let coordinator: AppCoordinator

    @Environment(\.theme) private var theme

    // MARK: - Convenience Accessors

    private var actionCoordinator: EmailActionCoordinator { coordinator.actionCoordinator }
    private var mailboxViewModel: MailboxViewModel { coordinator.mailboxViewModel }
    private var mailStore: MailStore { coordinator.mailStore }
    private var accountID: String { coordinator.accountID }
    private var fromAddress: String { coordinator.fromAddress }
    private var composeMode: ComposeMode { coordinator.composeMode }
    private var signatureForNew: String { coordinator.signatureForNew }
    private var signatureForReply: String { coordinator.signatureForReply }
    private var panelCoordinator: PanelCoordinator { coordinator.panelCoordinator }
    private var attachmentIndexer: AttachmentIndexer? { coordinator.attachmentIndexer }

    private var isMultiSelect: Bool { selectedEmailIDs.count > 1 }

    private var isEditingDraft: Bool {
        guard let email = selectedEmail else { return false }
        return email.isDraft
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.vertical, 8)
        .padding(.trailing, 8)
    }

    // MARK: - Bulk Actions

    private var bulkActionView: some View {
        BulkActionBarView(
            count: selectedEmailIDs.count,
            selectedFolder: selectedFolder,
            onArchive:     { actionCoordinator.bulkArchive(selectedEmails, onClear: { coordinator.clearSelection() }) },
            onDelete:      { actionCoordinator.bulkDelete(selectedEmails, onClear: { coordinator.clearSelection() }) },
            onMarkUnread:  { actionCoordinator.bulkMarkUnread(selectedEmails, onClear: { coordinator.deselectAll() }) },
            onMarkRead:    { actionCoordinator.bulkMarkRead(selectedEmails, onClear: { coordinator.deselectAll() }) },
            onToggleStar:  { for e in selectedEmails { actionCoordinator.toggleStarEmail(e) } },
            onMoveToInbox: { actionCoordinator.bulkMoveToInbox(selectedEmails, selectedFolder: selectedFolder, onClear: { coordinator.clearSelection() }) },
            onDeselectAll: { coordinator.deselectAll() }
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
            onDiscard: { coordinator.discardDraft(id: draftId) }
        )
        .id(draftId)
    }

    // MARK: - Email Detail

    private func emailDetailView(email: Email) -> some View {
        var view = EmailDetailView(
            email: email,
            accountID: accountID,
            attachmentIndexer: attachmentIndexer,
            onArchive: selectedFolder == .archive ? nil : { actionCoordinator.archiveEmail(email, selectNext: { coordinator.selectNext($0) }) },
            onDelete: selectedFolder == .trash ? nil : { actionCoordinator.deleteEmail(email, selectNext: { coordinator.selectNext($0) }) },
            onMoveToInbox: selectedFolder == .archive || selectedFolder == .trash
                ? { actionCoordinator.moveToInboxEmail(email, selectedFolder: selectedFolder, selectNext: { coordinator.selectNext($0) }) } : nil,
            onDeletePermanently: selectedFolder == .trash
                ? { actionCoordinator.deletePermanentlyEmail(email, selectNext: { coordinator.selectNext($0) }) } : nil,
            onMarkNotSpam: selectedFolder == .spam
                ? { actionCoordinator.markNotSpamEmail(email, selectNext: { coordinator.selectNext($0) }) } : nil,
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
            onReply: { mode in coordinator.startCompose(mode: mode) },
            onReplyAll: { mode in coordinator.startCompose(mode: mode) },
            onForward: { mode in coordinator.startCompose(mode: mode) },
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
                await UnsubscribeService.shared.unsubscribe(url: url, oneClick: oneClick, messageID: msgID, accountID: accountID)
            },
            onPrint: { msg, email in
                EmailPrintService.shared.printEmail(message: msg, email: email)
            },
            checkUnsubscribed: { msgID in
                UnsubscribeService.shared.isUnsubscribed(messageID: msgID, accountID: accountID)
            },
            extractBodyUnsubscribeURL: { html in
                UnsubscribeService.extractBodyUnsubscribeURL(from: html)
            },
            fromAddress: fromAddress
        )
        view.mailStore = mailStore
        return view.id(email.id)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 40))
                .foregroundColor(theme.textTertiary)
            Text(emptyStateMessage)
                .font(.system(size: 14))
                .foregroundColor(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.detailBackground)
    }

    private var emptyStateIcon: String {
        switch selectedFolder {
        case .drafts:        return "doc.text"
        case .sent:          return "paperplane"
        case .trash:         return "trash"
        case .spam:          return "exclamationmark.shield"
        case .starred:       return "star"
        case .archive:       return "archivebox"
        case .attachments:   return "paperclip"
        case .subscriptions: return "newspaper"
        default:             return "envelope.open"
        }
    }

    private var emptyStateMessage: String {
        switch selectedFolder {
        case .drafts:        return "Select a draft to edit"
        case .sent:          return "Select a sent email to view"
        case .starred:       return "Select a starred email to read"
        case .archive:       return "Select an archived email to read"
        case .attachments:   return "Select an email to view attachments"
        case .subscriptions: return "Select a subscription to view"
        default:             return "Select an email to read"
        }
    }
}
