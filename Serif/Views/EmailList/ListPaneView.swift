import SwiftUI

struct ListPaneView: View {
    let emails: [Email]
    let isLoading: Bool
    @Binding var selectedFolder: Folder
    let searchResetTrigger: Int
    @Binding var selectedEmail: Email?
    @Binding var selectedEmailIDs: Set<String>
    @Binding var searchFocusTrigger: Bool

    let actionCoordinator: EmailActionCoordinator
    let mailboxViewModel: MailboxViewModel

    let onSelectNext: (Email?) -> Void
    let onLoadCurrentFolder: () async -> Void
    let onEmptyTrashRequested: (Int) -> Void

    private var selectedEmails: [Email] {
        emails.filter { selectedEmailIDs.contains($0.id.uuidString) }
    }

    private func clearSelection() {
        selectedEmail = nil
        selectedEmailIDs = []
    }

    var body: some View {
        Group {
            if selectedFolder == .attachments {
                AttachmentsListView(
                    mailboxViewModel: mailboxViewModel,
                    selectedEmail: $selectedEmail
                )
            } else {
                emailList
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
    }

    private var emailList: some View {
        EmailListView(
            emails: emails,
            isLoading: isLoading,
            onLoadMore: { Task { await mailboxViewModel.loadMore() } },
            onSearch: { query in
                if query.isEmpty {
                    Task { await onLoadCurrentFolder() }
                } else {
                    Task { await mailboxViewModel.search(query: query) }
                }
            },
            onArchive:           { actionCoordinator.archiveEmail($0, selectNext: onSelectNext) },
            onDelete:            { actionCoordinator.deleteEmail($0, selectNext: onSelectNext) },
            onToggleStar:        { actionCoordinator.toggleStarEmail($0) },
            onMarkUnread:        { actionCoordinator.markUnreadEmail($0) },
            onMarkSpam:          { actionCoordinator.markSpamEmail($0, selectNext: onSelectNext) },
            onUnsubscribe:       { actionCoordinator.unsubscribeEmail($0) },
            onMoveToInbox:       { actionCoordinator.moveToInboxEmail($0, selectedFolder: selectedFolder, selectNext: onSelectNext) },
            onDeletePermanently: { actionCoordinator.deletePermanentlyEmail($0, selectNext: onSelectNext) },
            onMarkNotSpam:       { actionCoordinator.markNotSpamEmail($0, selectNext: onSelectNext) },
            onEmptyTrash: {
                actionCoordinator.emptyTrash(accountID: mailboxViewModel.accountID) { count in
                    onEmptyTrashRequested(count)
                }
            },
            onBulkArchive:    { actionCoordinator.bulkArchive(selectedEmails, onClear: clearSelection) },
            onBulkDelete:     { actionCoordinator.bulkDelete(selectedEmails, onClear: clearSelection) },
            onBulkMarkUnread: { actionCoordinator.bulkMarkUnread(selectedEmails) { selectedEmailIDs = [] } },
            onBulkMarkRead:   { actionCoordinator.bulkMarkRead(selectedEmails) { selectedEmailIDs = [] } },
            onBulkToggleStar: { for e in selectedEmails { actionCoordinator.toggleStarEmail(e) } },
            onRefresh:        { await onLoadCurrentFolder() },
            searchResetTrigger: searchResetTrigger,
            searchFocusTrigger: $searchFocusTrigger,
            selectedEmail: $selectedEmail,
            selectedEmailIDs: $selectedEmailIDs,
            selectedFolder: $selectedFolder
        )
    }
}
