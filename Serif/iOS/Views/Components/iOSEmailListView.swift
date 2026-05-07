import SwiftUI

struct iOSEmailListView: View {
    let emails: [Email]
    let isLoading: Bool
    @Binding var selectedEmail: Email?
    let onRefresh: () async -> Void
    var onArchive: ((Email) -> Void)?
    var onTrash: ((Email) -> Void)?
    var onToggleRead: ((Email) -> Void)?
    var onToggleStar: ((Email) -> Void)?
    var onReply: ((Email) -> Void)?
    var onReplyAll: ((Email) -> Void)?
    var onForward: ((Email) -> Void)?
    var onSpam: ((Email) -> Void)?
    var onLoadMore: (() -> Void)?
    var isLoadingMore: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            ForEach(emails) { email in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedEmail = email
                    }
                } label: {
                    iOSEmailRow(email: email, isSelected: selectedEmail?.id == email.id)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    selectedEmail?.id == email.id
                        ? theme.selectedCardBackground
                        : Color.clear
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if let onTrash {
                        Button(role: .destructive) {
                            onTrash(email)
                        } label: {
                            Label("Trash", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    if let onArchive {
                        Button {
                            onArchive(email)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if let onToggleRead {
                        Button {
                            onToggleRead(email)
                        } label: {
                            Label(
                                email.isRead ? "Unread" : "Read",
                                systemImage: email.isRead ? "envelope.badge" : "envelope.open"
                            )
                        }
                        .tint(.blue)
                    }

                    if let onToggleStar {
                        Button {
                            onToggleStar(email)
                        } label: {
                            Label(
                                email.isStarred ? "Unstar" : "Star",
                                systemImage: email.isStarred ? "star.slash" : "star.fill"
                            )
                        }
                        .tint(.yellow)
                    }
                }
                .contextMenu {
                    EmailRowContextMenu(
                        email: email,
                        onReply: onReply,
                        onReplyAll: onReplyAll,
                        onForward: onForward,
                        onArchive: onArchive,
                        onTrash: onTrash,
                        onToggleRead: onToggleRead,
                        onToggleStar: onToggleStar,
                        onSpam: onSpam
                    )
                }
            }

            // Load more sentinel
            if !emails.isEmpty && onLoadMore != nil {
                Section {
                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 12)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        Color.clear
                            .frame(height: 1)
                            .onAppear { onLoadMore?() }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if isLoading && emails.isEmpty {
                skeletonList
            }
            if !isLoading && emails.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(theme.textTertiary)
                    Text("No emails")
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                }
            }
        }
        .refreshable {
            await onRefresh()
        }
    }

    // MARK: - Skeleton Loading

    private var skeletonList: some View {
        List {
            ForEach(0..<8, id: \.self) { _ in
                skeletonRow
                    .listRowSeparator(.visible)
                    .listRowBackground(theme.listBackground)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.listBackground)
        .redacted(reason: .placeholder)
        .shimmer()
    }

    private var skeletonRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(theme.textTertiary.opacity(0.15))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            Circle()
                .fill(theme.textTertiary.opacity(0.15))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.textTertiary.opacity(0.15))
                        .frame(width: 120, height: 13)
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.textTertiary.opacity(0.1))
                        .frame(width: 50, height: 11)
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.textTertiary.opacity(0.15))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.textTertiary.opacity(0.1))
                    .frame(height: 11)
                    .padding(.trailing, 40)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shimmer Effect

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = UIScreen.main.bounds.width
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Context Menu (extracted to reduce view recomputation)

private struct EmailRowContextMenu: View {
    let email: Email
    let onReply: ((Email) -> Void)?
    let onReplyAll: ((Email) -> Void)?
    let onForward: ((Email) -> Void)?
    let onArchive: ((Email) -> Void)?
    let onTrash: ((Email) -> Void)?
    let onToggleRead: ((Email) -> Void)?
    let onToggleStar: ((Email) -> Void)?
    let onSpam: ((Email) -> Void)?

    var body: some View {
        if onReply != nil {
            Button { onReply?(email) } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
        if onReplyAll != nil {
            Button { onReplyAll?(email) } label: {
                Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
            }
        }
        if onForward != nil {
            Button { onForward?(email) } label: {
                Label("Forward", systemImage: "arrowshape.turn.up.right")
            }
        }

        if onArchive != nil || onTrash != nil {
            Divider()
        }

        if let onArchive {
            Button { onArchive(email) } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
        if let onTrash {
            Button(role: .destructive) { onTrash(email) } label: {
                Label {
                    Text("Move to Trash")
                } icon: {
                    Image(systemName: "trash")
                        .renderingMode(.template)
                        .foregroundStyle(.red)
                }
            }
        }

        if onToggleRead != nil || onToggleStar != nil {
            Divider()
        }

        if let onToggleRead {
            Button { onToggleRead(email) } label: {
                Label(
                    email.isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: email.isRead ? "envelope.badge" : "envelope.open"
                )
            }
        }
        if let onToggleStar {
            Button { onToggleStar(email) } label: {
                Label(
                    email.isStarred ? "Remove Star" : "Add Star",
                    systemImage: email.isStarred ? "star.slash" : "star"
                )
            }
        }

        if onSpam != nil {
            Divider()
        }

        if let onSpam {
            Button(role: .destructive) { onSpam(email) } label: {
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
}
