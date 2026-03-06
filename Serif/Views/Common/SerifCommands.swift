import SwiftUI

// MARK: - Commands

struct SerifCommands: Commands {
    @FocusedObject private var coordinator: AppCoordinator?

    private var selectedEmail: Email? { coordinator?.selectedEmail }
    private var hasSelection: Bool { selectedEmail != nil }
    private var isInbox: Bool { coordinator?.selectedFolder == .inbox }

    /// Read live state from the mailbox viewmodel (source of truth) rather than
    /// the selectedEmail snapshot which may be stale.
    private var liveMessage: GmailMessage? {
        guard let msgID = selectedEmail?.gmailMessageID else { return nil }
        return coordinator?.mailboxViewModel.messages.first { $0.id == msgID }
    }
    private var isStarred: Bool { liveMessage?.isStarred ?? selectedEmail?.isStarred ?? false }
    private var isRead: Bool { !(liveMessage?.isUnread ?? !(selectedEmail?.isRead ?? true)) }

    var body: some Commands {
        messageMenu
        mailboxMenu
        viewMenu
        settingsMenu
    }

    // MARK: - Message

    private var messageMenu: some Commands {
        CommandMenu("Message") {
            Button("Archive") {
                guard let coordinator, let email = selectedEmail else { return }
                coordinator.actionCoordinator.archiveEmail(email, selectNext: { coordinator.selectNext($0) })
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!hasSelection)

            Button("Delete") {
                guard let coordinator, let email = selectedEmail else { return }
                coordinator.actionCoordinator.deleteEmail(email, selectNext: { coordinator.selectNext($0) })
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!hasSelection)

            Button("Move to Inbox") {
                guard let coordinator, let email = selectedEmail else { return }
                coordinator.actionCoordinator.moveToInboxEmail(email, selectedFolder: coordinator.selectedFolder, selectNext: { coordinator.selectNext($0) })
            }
            .disabled(!hasSelection || coordinator?.selectedFolder == .inbox)

            Divider()

            Button(isStarred ? "Remove Star" : "Add Star") {
                guard let coordinator, let msgID = selectedEmail?.gmailMessageID else { return }
                Task { await coordinator.mailboxViewModel.toggleStar(msgID, isStarred: isStarred) }
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(!hasSelection)

            Button(isRead ? "Mark as Unread" : "Mark as Read") {
                guard let coordinator, let email = selectedEmail, let msgID = email.gmailMessageID else { return }
                if isRead {
                    coordinator.actionCoordinator.markUnreadEmail(email)
                } else if let message = coordinator.mailboxViewModel.messages.first(where: { $0.id == msgID }) {
                    Task { await coordinator.mailboxViewModel.markAsRead(message) }
                }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!hasSelection)
        }
    }

    // MARK: - Mailbox

    private var mailboxMenu: some Commands {
        CommandMenu("Mailbox") {
            Button("Compose New Message") {
                coordinator?.composeNewEmail()
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("Refresh") {
                guard let coordinator else { return }
                Task { await coordinator.loadCurrentFolder() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Search") {
                coordinator?.searchFocusTrigger = true
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }

    // MARK: - View

    private var viewMenu: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Sidebar") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    coordinator?.sidebarExpanded.toggle()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
    }

    // MARK: - Settings

    private var settingsMenu: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                coordinator?.panelCoordinator.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
