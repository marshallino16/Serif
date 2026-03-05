import SwiftUI

@MainActor
class EmailActionCoordinator: ObservableObject {
    let mailboxViewModel: MailboxViewModel
    let mailStore: MailStore

    init(mailboxViewModel: MailboxViewModel, mailStore: MailStore) {
        self.mailboxViewModel = mailboxViewModel
        self.mailStore = mailStore
    }

    // MARK: - Single email actions

    func archiveEmail(_ email: Email, selectNext: (Email?) -> Void) {
        guard let msgID = email.gmailMessageID else { return }
        let vm = mailboxViewModel
        let removed = vm.removeOptimistically(msgID)
        selectNext(nil)
        UndoActionManager.shared.schedule(
            label: "Archived",
            onConfirm: { Task { await vm.archive(msgID) } },
            onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
        )
    }

    func deleteEmail(_ email: Email, selectNext: (Email?) -> Void) {
        // Draft-specific path: delete from mailStore directly
        if email.isDraft {
            if let gid = email.gmailDraftID {
                let accountID = mailboxViewModel.accountID
                Task { try? await GmailSendService.shared.deleteDraft(draftID: gid, accountID: accountID) }
            }
            mailStore.deleteDraft(id: email.id)
            selectNext(nil)
            return
        }
        guard let msgID = email.gmailMessageID else { return }
        let vm = mailboxViewModel
        let removed = vm.removeOptimistically(msgID)
        selectNext(nil)
        UndoActionManager.shared.schedule(
            label: "Moved to Trash",
            onConfirm: { Task { await vm.trash(msgID) } },
            onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
        )
    }

    func toggleStarEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        Task { await mailboxViewModel.toggleStar(msgID, isStarred: email.isStarred) }
    }

    func markUnreadEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        Task { await mailboxViewModel.markAsUnread(msgID) }
    }

    func markSpamEmail(_ email: Email, selectNext: @escaping (Email?) -> Void) {
        guard let msgID = email.gmailMessageID else { return }
        Task {
            await mailboxViewModel.spam(msgID)
            selectNext(nil)
        }
    }

    func unsubscribeEmail(_ email: Email) {
        guard let url = email.unsubscribeURL else { return }
        SubscriptionsStore.shared.removeEntry(for: email)
        Task { await UnsubscribeService.shared.unsubscribe(url: url, oneClick: false) }
    }

    func moveToInboxEmail(_ email: Email, selectedFolder: Folder, selectNext: (Email?) -> Void) {
        guard let msgID = email.gmailMessageID else { return }
        let vm = mailboxViewModel
        let removed = vm.removeOptimistically(msgID)
        selectNext(nil)
        if selectedFolder == .trash {
            UndoActionManager.shared.schedule(
                label: "Moved to Inbox",
                onConfirm: { Task { await vm.untrash(msgID) } },
                onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
            )
        } else {
            UndoActionManager.shared.schedule(
                label: "Moved to Inbox",
                onConfirm: { Task { await vm.moveToInbox(msgID) } },
                onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
            )
        }
    }

    func deletePermanentlyEmail(_ email: Email, selectNext: (Email?) -> Void) {
        guard let msgID = email.gmailMessageID else { return }
        let vm = mailboxViewModel
        let removed = vm.removeOptimistically(msgID)
        selectNext(nil)
        UndoActionManager.shared.schedule(
            label: "Deleted permanently",
            onConfirm: { Task { await vm.deletePermanently(msgID) } },
            onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
        )
    }

    func markNotSpamEmail(_ email: Email, selectNext: (Email?) -> Void) {
        guard let msgID = email.gmailMessageID else { return }
        let vm = mailboxViewModel
        let removed = vm.removeOptimistically(msgID)
        selectNext(nil)
        UndoActionManager.shared.schedule(
            label: "Moved to Inbox",
            onConfirm: { Task { await vm.unspam(msgID) } },
            onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
        )
    }

    func emptyTrash(accountID: String, onConfirm: @escaping (Int) -> Void) {
        guard !accountID.isEmpty else { return }
        Task {
            var count: Int
            do {
                let label = try await GmailLabelService.shared.getLabel(id: "TRASH", accountID: accountID)
                count = label.messagesTotal ?? 0
            } catch {
                count = mailboxViewModel.emails.count
            }
            guard count > 0 else { return }
            onConfirm(count)
        }
    }

    func emptySpam(accountID: String, onConfirm: @escaping (Int) -> Void) {
        guard !accountID.isEmpty else { return }
        Task {
            var count: Int
            do {
                let label = try await GmailLabelService.shared.getLabel(id: "SPAM", accountID: accountID)
                count = label.messagesTotal ?? 0
            } catch {
                count = mailboxViewModel.emails.count
            }
            guard count > 0 else { return }
            onConfirm(count)
        }
    }

    // MARK: - Bulk actions

    func bulkArchive(_ emails: [Email], onClear: () -> Void) {
        let vm = mailboxViewModel
        let msgIDs = emails.compactMap(\.gmailMessageID)
        let removed = msgIDs.compactMap { vm.removeOptimistically($0) }
        onClear()
        UndoActionManager.shared.schedule(
            label: "Archived \(msgIDs.count) emails",
            onConfirm: { Task { for id in msgIDs { await vm.archive(id) } } },
            onUndo:    { for msg in removed { vm.restoreOptimistically(msg) } }
        )
    }

    func bulkDelete(_ emails: [Email], onClear: () -> Void) {
        let vm = mailboxViewModel
        let msgIDs = emails.compactMap(\.gmailMessageID)
        let removed = msgIDs.compactMap { vm.removeOptimistically($0) }
        onClear()
        UndoActionManager.shared.schedule(
            label: "Trashed \(msgIDs.count) emails",
            onConfirm: { Task { for id in msgIDs { await vm.trash(id) } } },
            onUndo:    { for msg in removed { vm.restoreOptimistically(msg) } }
        )
    }

    func bulkMarkUnread(_ emails: [Email], onClear: () -> Void) {
        let msgIDs = emails.compactMap(\.gmailMessageID)
        onClear()
        Task { for id in msgIDs { await mailboxViewModel.markAsUnread(id) } }
    }

    func bulkMarkRead(_ emails: [Email], onClear: () -> Void) {
        let msgs = emails.compactMap { e -> GmailMessage? in
            guard let msgID = e.gmailMessageID else { return nil }
            return mailboxViewModel.messages.first { $0.id == msgID }
        }
        onClear()
        Task { for msg in msgs { await mailboxViewModel.markAsRead(msg) } }
    }

    func bulkMoveToInbox(_ emails: [Email], selectedFolder: Folder, onClear: () -> Void) {
        let vm = mailboxViewModel
        let msgIDs = emails.compactMap(\.gmailMessageID)
        let removed = msgIDs.compactMap { vm.removeOptimistically($0) }
        onClear()
        if selectedFolder == .trash {
            UndoActionManager.shared.schedule(
                label: "Moved \(msgIDs.count) to Inbox",
                onConfirm: { Task { for id in msgIDs { await vm.untrash(id) } } },
                onUndo:    { for msg in removed { vm.restoreOptimistically(msg) } }
            )
        } else {
            UndoActionManager.shared.schedule(
                label: "Moved \(msgIDs.count) to Inbox",
                onConfirm: { Task { for id in msgIDs { await vm.moveToInbox(id) } } },
                onUndo:    { for msg in removed { vm.restoreOptimistically(msg) } }
            )
        }
    }
}
