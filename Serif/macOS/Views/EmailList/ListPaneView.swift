import SwiftUI

struct ListPaneView: View {
    let emails: [Email]
    let isLoading: Bool
    @Binding var selectedFolder: Folder
    let searchResetTrigger: Int
    @Binding var selectedEmail: Email?
    @Binding var selectedEmailIDs: Set<String>
    @Binding var searchFocusTrigger: Bool

    let coordinator: AppCoordinator

    // MARK: - Convenience Accessors

    private var actionCoordinator: EmailActionCoordinator { coordinator.actionCoordinator }
    private var mailboxViewModel: MailboxViewModel { coordinator.mailboxViewModel }

    private var selectedEmails: [Email] {
        emails.filter { selectedEmailIDs.contains($0.id.uuidString) }
    }

    private func clearSelection() {
        selectedEmail = nil
        selectedEmailIDs = []
    }

    var body: some View {
        emailList
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
    }

    private var emailList: some View {
        EmailListView(
            emails: emails,
            isLoading: isLoading,
            onLoadMore: { Task { await mailboxViewModel.loadMore() } },
            onSearch: { query in
                if query.isEmpty {
                    Task { await coordinator.loadCurrentFolder() }
                } else {
                    Task { await mailboxViewModel.search(query: query) }
                }
            },
            onArchive:           { actionCoordinator.archiveEmail($0, selectNext: { coordinator.selectNext($0) }) },
            onDelete:            { actionCoordinator.deleteEmail($0, selectNext: { coordinator.selectNext($0) }) },
            onToggleStar:        { actionCoordinator.toggleStarEmail($0) },
            onMarkUnread:        { actionCoordinator.markUnreadEmail($0) },
            onMarkSpam:          { actionCoordinator.markSpamEmail($0, selectNext: { coordinator.selectNext($0) }) },
            onUnsubscribe:       { actionCoordinator.unsubscribeEmail($0) },
            onMoveToInbox:       { actionCoordinator.moveToInboxEmail($0, selectedFolder: selectedFolder, selectNext: { coordinator.selectNext($0) }) },
            onDeletePermanently: { actionCoordinator.deletePermanentlyEmail($0, selectNext: { coordinator.selectNext($0) }) },
            onMarkNotSpam:       { actionCoordinator.markNotSpamEmail($0, selectNext: { coordinator.selectNext($0) }) },
            onEmptyTrash: {
                actionCoordinator.emptyTrash(accountID: mailboxViewModel.accountID) { count in
                    coordinator.emptyTrashRequested(count: count)
                }
            },
            onEmptySpam: {
                actionCoordinator.emptySpam(accountID: mailboxViewModel.accountID) { count in
                    coordinator.emptySpamRequested(count: count)
                }
            },
            onBulkArchive:    { actionCoordinator.bulkArchive(selectedEmails, onClear: clearSelection) },
            onBulkDelete:     { actionCoordinator.bulkDelete(selectedEmails, onClear: clearSelection) },
            onBulkMarkUnread: { actionCoordinator.bulkMarkUnread(selectedEmails) { selectedEmailIDs = [] } },
            onBulkMarkRead:   { actionCoordinator.bulkMarkRead(selectedEmails) { selectedEmailIDs = [] } },
            onBulkToggleStar: { for e in selectedEmails { actionCoordinator.toggleStarEmail(e) } },
            onRefresh:        { await coordinator.loadCurrentFolder() },
            searchResetTrigger: searchResetTrigger,
            searchFocusTrigger: $searchFocusTrigger,
            selectedEmail: $selectedEmail,
            selectedEmailIDs: $selectedEmailIDs,
            selectedFolder: $selectedFolder
        )
    }
}
