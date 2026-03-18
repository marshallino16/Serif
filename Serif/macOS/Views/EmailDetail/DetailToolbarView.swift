import SwiftUI

struct DetailToolbarView: View {
    let email: Email
    let detailVM: EmailDetailViewModel
    let isMailingList: Bool
    let resolvedUnsubscribeURL: URL?
    let oneClick: Bool
    let alreadyUnsubscribed: Bool
    var onArchive: (() -> Void)?
    var onDelete: (() -> Void)?
    var onMoveToInbox: (() -> Void)?
    var onDeletePermanently: (() -> Void)?
    var onMarkNotSpam: (() -> Void)?
    var onToggleStar: ((Bool) -> Void)?
    var onMarkUnread: (() -> Void)?
    var onReply: ((ComposeMode) -> Void)?
    var onReplyAll: ((ComposeMode) -> Void)?
    var onForward: ((ComposeMode) -> Void)?
    var onShowOriginal: ((EmailDetailViewModel) -> Void)?
    var onDownloadMessage: ((EmailDetailViewModel) -> Void)?
    var onUnsubscribe: ((URL, Bool, String?) async -> Bool)?
    var onPrint: ((GmailMessage, Email) -> Void)?
    let replyMode: () -> ComposeMode
    let replyAllMode: () -> ComposeMode
    let forwardMode: () -> ComposeMode

    @State private var isUnsubscribing = false
    @Binding var didUnsubscribe: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Spacer()

            // Unsubscribe button — only shown for mailing lists
            if isMailingList, let url = resolvedUnsubscribeURL {
                if alreadyUnsubscribed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Unsubscribed")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(theme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.hoverBackground)
                    .cornerRadius(6)
                } else {
                    Button {
                        isUnsubscribing = true
                        Task {
                            let msgID = email.gmailMessageID
                            let success = await onUnsubscribe?(url, oneClick, msgID) ?? false
                            isUnsubscribing = false
                            if success { didUnsubscribe = true }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isUnsubscribing {
                                ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                            }
                            Text("Unsubscribe")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(theme.destructive)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.destructive.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUnsubscribing)
                    .help(oneClick ? "One-click unsubscribe" : "Open unsubscribe page")
                }

                Divider().frame(height: 16)
            }

            if let onArchive {
                toolbarButton(icon: "archivebox", label: "Archive") { onArchive() }
            }
            if let onDelete {
                toolbarButton(icon: "trash", label: "Delete") { onDelete() }
            }
            if let onMoveToInbox {
                toolbarButton(icon: "tray.and.arrow.down", label: "Move to Inbox") { onMoveToInbox() }
            }

            Divider().frame(height: 16)

            Menu {
                Section {
                    Button { onReply?(replyMode()) }    label: { Label("Reply",     systemImage: "arrowshape.turn.up.left") }
                    Button { onReplyAll?(replyAllMode()) } label: { Label("Reply All", systemImage: "arrowshape.turn.up.left.2") }
                    Button { onForward?(forwardMode()) }  label: { Label("Forward",   systemImage: "arrowshape.turn.up.right") }
                }
                Divider()
                Section {
                    Button { onMarkUnread?() } label: { Label("Mark as Unread",     systemImage: "envelope.badge") }
                    Button {
                        let starred = detailVM.latestMessage?.isStarred ?? email.isStarred
                        detailVM.toggleStar()
                        onToggleStar?(starred)
                    } label: {
                        let starred = detailVM.latestMessage?.isStarred ?? email.isStarred
                        Label(starred ? "Remove from Favorites" : "Add to Favorites", systemImage: starred ? "star.slash" : "star")
                    }
                }
                Divider()
                Section {
                    Button {
                        if let msg = detailVM.latestMessage {
                            onPrint?(msg, email)
                        }
                    } label: { Label("Print", systemImage: "printer") }
                    Button { onDownloadMessage?(detailVM) } label: { Label("Download Message", systemImage: "arrow.down.circle") }
                    Button { onShowOriginal?(detailVM) } label: { Label("Show Original",    systemImage: "doc.text") }
                }
                Divider()
                Section {
                    // TODO: Implement mute thread and block sender features
                    // Button { } label: { Label("Mute Thread", systemImage: "bell.slash") }
                    // Button { } label: { Label("Block Sender", systemImage: "hand.raised") }
                    if let onMarkNotSpam {
                        Button { onMarkNotSpam() } label: { Label("Not Spam", systemImage: "tray.and.arrow.down") }
                    } else {
                        Button(role: .destructive) { onDelete?() } label: { Label("Report as Spam", systemImage: "exclamationmark.shield") }
                    }
                    if let onDeletePermanently {
                        Button(role: .destructive) { onDeletePermanently() } label: { Label("Delete Permanently", systemImage: "trash.slash") }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("More")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
