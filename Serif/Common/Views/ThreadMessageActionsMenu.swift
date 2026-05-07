import SwiftUI

/// Context menu items for a single message inside a thread (long-press / right-click on a bubble).
/// All actions operate on a specific message ID, not on the whole thread.
struct ThreadMessageActionsMenu: View {
    let message: GmailMessage
    let onReply: () -> Void
    let onReplyAll: () -> Void
    let onForward: () -> Void
    let onToggleStar: () -> Void
    let onMarkUnread: () -> Void
    let onArchive: () -> Void
    let onTrash: () -> Void
    let onSpam: () -> Void

    private var isStarred: Bool {
        message.labelIds?.contains("STARRED") ?? false
    }

    var body: some View {
        Button { onReply() } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }
        Button { onReplyAll() } label: {
            Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
        }
        Button { onForward() } label: {
            Label("Forward", systemImage: "arrowshape.turn.up.right")
        }

        Divider()

        Button { onToggleStar() } label: {
            Label(
                isStarred ? "Remove Star" : "Add Star",
                systemImage: isStarred ? "star.slash" : "star"
            )
        }

        Button { onMarkUnread() } label: {
            Label("Mark as Unread", systemImage: "envelope.badge")
        }

        Divider()

        Button { onArchive() } label: {
            Label("Archive", systemImage: "archivebox")
        }

        Button(role: .destructive) { onTrash() } label: {
            Label {
                Text("Move to Trash")
            } icon: {
                Image(systemName: "trash")
                    .renderingMode(.template)
                    .foregroundStyle(.red)
            }
        }

        Divider()

        Button(role: .destructive) { onSpam() } label: {
            Label {
                Text("Report as Spam")
            } icon: {
                Image(systemName: "exclamationmark.shield")
                    .renderingMode(.template)
                    .foregroundStyle(.red)
            }
        }
    }
}
