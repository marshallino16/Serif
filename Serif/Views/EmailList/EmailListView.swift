import SwiftUI

struct EmailListView: View {
    let emails: [Email]
    let isLoading: Bool
    let onLoadMore: () -> Void
    let onSearch: (String) -> Void
    let onArchive: ((Email) -> Void)?
    let onDelete: ((Email) -> Void)?
    let onToggleStar: ((Email) -> Void)?
    let onMarkUnread: ((Email) -> Void)?
    let onMarkSpam: ((Email) -> Void)?
    let searchResetTrigger: Int
    @Binding var selectedEmail: Email?
    @Binding var selectedFolder: Folder
    @State private var searchText = ""
    @State private var searchFocusTrigger = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var sortOrder: EmailSortOrder = .dateNewest
    @ObservedObject private var swipeCoordinator = SwipeCoordinator.shared
    @Environment(\.theme) private var theme

    private var sortedEmails: [Email] {
        switch sortOrder {
        case .dateNewest, .unreadFirst: return emails  // unread: filtered at API level
        case .dateOldest:               return emails.reversed()
        case .sender:                   return emails.sorted { $0.sender.name.lowercased() < $1.sender.name.lowercased() }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(selectedFolder.rawValue)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(theme.textPrimary)

                    Spacer()

                    Menu {
                        Button { sortOrder = .dateNewest }  label: { Label("Date (Newest)",  systemImage: sortOrder == .dateNewest  ? "checkmark" : "") }
                        Button { sortOrder = .dateOldest }  label: { Label("Date (Oldest)",  systemImage: sortOrder == .dateOldest  ? "checkmark" : "") }
                        Button { sortOrder = .sender }       label: { Label("Sender",         systemImage: sortOrder == .sender      ? "checkmark" : "") }
                        Button { sortOrder = .unreadFirst } label: { Label("Unread first",   systemImage: sortOrder == .unreadFirst ? "checkmark" : "") }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sortOrder.label)
                                .font(.system(size: 12))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.cardBackground)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                SearchBarView(text: $searchText, focusTrigger: $searchFocusTrigger)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .background(theme.divider)

            if isLoading && emails.isEmpty {
                // Skeleton loading state
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(0..<9, id: \.self) { _ in
                            EmailSkeletonRowView()
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sortedEmails) { email in
                            SwipeableEmailRow(
                                email: email,
                                isSelected: selectedEmail?.id == email.id,
                                onTap: { selectedEmail = email },
                                onArchive: onArchive.map { action in { action(email) } },
                                onDelete:  onDelete.map  { action in { action(email) } }
                            )
                            .contextMenu { emailContextMenu(for: email) }
                        }

                        // Load-more sentinel
                        if !emails.isEmpty && searchText.isEmpty {
                            Color.clear
                                .frame(height: 1)
                                .onAppear { onLoadMore() }
                        }

                        // Inline loading indicator for load-more
                        if isLoading && !emails.isEmpty {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(theme.textTertiary)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollDisabled(swipeCoordinator.isSwipeActive)
                .focusable()
                .focusEffectDisabled(true)
                .onKeyPress(.upArrow) {
                    navigateToPrevious()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    navigateToNext()
                    return .handled
                }
            }

            // Hidden button for ⌘F
            Button("") { searchFocusTrigger = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .background(theme.listBackground)
        .onChange(of: searchResetTrigger) { _ in
            searchText = ""
            sortOrder = .dateNewest
        }
        .onChange(of: sortOrder) { newSort in
            switch newSort {
            case .unreadFirst: onSearch("is:unread")
            default:           onSearch(searchText)   // restores folder or current search
            }
        }
        .onChange(of: searchText) { query in
            searchDebounceTask?.cancel()
            if query.isEmpty {
                onSearch("")
            } else {
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    onSearch(query)
                }
            }
        }
    }

    @ViewBuilder
    private func emailContextMenu(for email: Email) -> some View {
        Button { } label: { Label("Reply",     systemImage: "arrowshape.turn.up.left") }
        Button { } label: { Label("Reply All", systemImage: "arrowshape.turn.up.left.2") }
        Button { } label: { Label("Forward",   systemImage: "arrowshape.turn.up.right") }

        Divider()

        Button { onArchive?(email) } label: { Label("Archive",       systemImage: "archivebox") }
        Button(role: .destructive) { onDelete?(email) } label: { Label("Move to Trash", systemImage: "trash") }

        Divider()

        Button { onToggleStar?(email) } label: {
            Label(email.isStarred ? "Remove Star" : "Add Star",
                  systemImage: email.isStarred ? "star.slash" : "star")
        }
        Button { onMarkUnread?(email) } label: { Label("Mark as Unread", systemImage: "envelope.badge") }

        Divider()

        Button(role: .destructive) { onMarkSpam?(email) } label: {
            Label("Report as Spam", systemImage: "exclamationmark.shield")
        }
    }

    private func navigateToPrevious() {
        guard let current = selectedEmail,
              let index = emails.firstIndex(where: { $0.id == current.id }),
              index > 0 else { return }
        selectedEmail = emails[index - 1]
    }

    private func navigateToNext() {
        guard let current = selectedEmail,
              let index = emails.firstIndex(where: { $0.id == current.id }),
              index < emails.count - 1 else { return }
        selectedEmail = emails[index + 1]
    }
}

// MARK: - Sort Order

enum EmailSortOrder {
    case dateNewest, dateOldest, sender, unreadFirst

    var label: String {
        switch self {
        case .dateNewest:  return "Recent"
        case .dateOldest:  return "Oldest"
        case .sender:      return "Sender"
        case .unreadFirst: return "Unread"
        }
    }
}

// MARK: - Skeleton Row

private struct EmailSkeletonRowView: View {
    @Environment(\.theme) private var theme
    @State private var animate = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(theme.textTertiary.opacity(0.12))
                .frame(width: 6, height: 6)

            Circle()
                .fill(theme.textTertiary.opacity(animate ? 0.1 : 0.2))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.textTertiary.opacity(animate ? 0.1 : 0.2))
                        .frame(width: 120, height: 10)
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.textTertiary.opacity(animate ? 0.1 : 0.2))
                        .frame(width: 38, height: 9)
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.textTertiary.opacity(animate ? 0.1 : 0.2))
                    .frame(height: 9)
                    .padding(.trailing, 40)
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.textTertiary.opacity(animate ? 0.1 : 0.2))
                    .frame(height: 8)
                    .padding(.trailing, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}
