import SwiftUI

struct SidebarView: View {
    @Binding var selectedFolder: Folder
    @Binding var selectedInboxCategory: InboxCategory?
    @Binding var selectedAccountID: String?
    @Binding var showSettings: Bool
    @Binding var isExpanded: Bool
    @Binding var showHelp: Bool
    @Binding var showDebug: Bool
    @ObservedObject var authViewModel: AuthViewModel
    var categoryUnreadCounts: [InboxCategory: Int] = [:]
    @Environment(\.theme) private var theme

    @State private var inboxExpanded = true

    private var sidebarWidth: CGFloat { isExpanded ? 200 : 60 }

    private var selectedAccount: GmailAccount? {
        authViewModel.accounts.first { $0.id == selectedAccountID }
            ?? authViewModel.accounts.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Logo
            if isExpanded {
                HStack {
                    Text("Serif")
                        .font(.custom("PPLocomotiveNew-Light", size: 20))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 52)
            }

            // Account switcher
            accountsSection
                .padding(.bottom, isExpanded ? 12 : 8)

            // Divider
            if isExpanded {
                Rectangle()
                    .fill(theme.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // Folder navigation
            VStack(spacing: 2) {
                ForEach(Folder.allCases) { folder in
                    if folder == .inbox {
                        inboxSection
                    } else {
                        SidebarItemView(
                            folder: folder,
                            isSelected: selectedFolder == folder,
                            isExpanded: isExpanded
                        ) {
                            selectedFolder = folder
                            selectedInboxCategory = nil
                        }
                    }
                }
            }
            .padding(.horizontal, isExpanded ? 8 : 0)

            Spacer()

            // Bottom actions
            VStack(spacing: 2) {
                #if DEBUG
                sidebarButton(icon: "ladybug.fill", label: "Debug") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showDebug = true }
                }
                #endif
                sidebarButton(icon: "gearshape.fill", label: "Settings") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showSettings = true }
                }
                sidebarButton(icon: "questionmark.circle", label: "Help") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showHelp = true }
                }
            }
            .padding(.horizontal, isExpanded ? 8 : 0)
            .padding(.bottom, 16)
        }
        .frame(width: sidebarWidth)
        .background(theme.sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.vertical, 8)
        .padding(.leading, 8)
    }

    // MARK: - Account Switcher

    private var accountsSection: some View {
        Group {
            if isExpanded {
                HStack(spacing: 6) {
                    ForEach(authViewModel.accounts) { account in
                        accountBubble(account: account, size: 28)
                    }
                    addAccountButton(size: 28)
                    Spacer()
                }
                .padding(.horizontal, 16)
            } else {
                VStack {
                    if let account = selectedAccount {
                        accountBubble(account: account, size: 34)
                    } else {
                        addAccountButton(size: 34)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func accountBubble(account: GmailAccount, size: CGFloat) -> some View {
        let isSelected = account.id == selectedAccountID
            || (selectedAccountID == nil && account.id == authViewModel.accounts.first?.id)
        let initial = String(account.displayName.prefix(1)).uppercased()

        return Button {
            selectedAccountID = account.id
        } label: {
            ZStack {
                // Base circle
                Circle().fill(isSelected ? theme.accentPrimary : theme.hoverBackground)
                if !isSelected && account.profilePictureURL == nil {
                    Circle().strokeBorder(theme.divider, lineWidth: 1)
                }

                if let url = account.profilePictureURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill().clipShape(Circle())
                        } else {
                            Text(initial)
                                .font(.system(size: size * 0.38, weight: .semibold))
                                .foregroundColor(isSelected ? .white : theme.textSecondary)
                        }
                    }
                } else {
                    Text(initial)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundColor(isSelected ? .white : theme.textSecondary)
                }

                // Selection ring (photo case only)
                if isSelected && account.profilePictureURL != nil {
                    Circle().strokeBorder(theme.accentPrimary, lineWidth: 2)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .help(account.email)
    }

    private func addAccountButton(size: CGFloat) -> some View {
        Button {
            Task { await authViewModel.signIn() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .foregroundColor(theme.divider)
                Image(systemName: "plus")
                    .font(.system(size: size * 0.32, weight: .medium))
                    .foregroundColor(theme.textTertiary)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .opacity(authViewModel.isSigningIn ? 0.5 : 1)
        .disabled(authViewModel.isSigningIn)
        .help("Add account")
    }

    // MARK: - Inbox super-category

    private var inboxSection: some View {
        VStack(spacing: 2) {
            // Parent row
            InboxParentRow(
                isSelected: selectedFolder == .inbox,
                isExpanded: isExpanded,
                inboxExpanded: $inboxExpanded,
                theme: theme
            ) {
                selectedFolder = .inbox
                selectedInboxCategory = .all
                withAnimation(.easeInOut(duration: 0.2)) { inboxExpanded.toggle() }
            }

            // Subcategories (expanded sidebar only)
            if isExpanded && inboxExpanded {
                ForEach(InboxCategory.allCases) { category in
                    InboxCategoryRow(
                        category: category,
                        isSelected: selectedFolder == .inbox && selectedInboxCategory == category,
                        unreadCount: categoryUnreadCounts[category] ?? 0,
                        theme: theme
                    ) {
                        selectedFolder = .inbox
                        selectedInboxCategory = category
                    }
                }
            }
        }
    }

    // MARK: - Generic bottom button

    private func sidebarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isExpanded {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 20)
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(Rectangle())
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(theme.textTertiary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inbox Parent Row

private struct InboxParentRow: View {
    let isSelected: Bool
    let isExpanded: Bool
    @Binding var inboxExpanded: Bool
    let theme: Theme
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            if isExpanded {
                HStack(spacing: 10) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? theme.accentPrimary : (isHovered ? theme.textSecondary : theme.textTertiary))
                        .frame(width: 20)

                    Text("Inbox")
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? theme.textPrimary : (isHovered ? theme.textSecondary : theme.textTertiary))

                    Spacer()

                    // Chevron to expand/collapse subcategories
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { inboxExpanded.toggle() }
                    } label: {
                        Image(systemName: inboxExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? theme.accentPrimary.opacity(0.12) : (isHovered ? theme.hoverBackground : Color.clear))
                )
                .contentShape(Rectangle())
            } else {
                // Collapsed: just the icon with dot if needed
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10).fill(theme.accentPrimary.opacity(0.15))
                    }
                    Image(systemName: "tray.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isSelected ? theme.accentPrimary : (isHovered ? theme.textSecondary : theme.textTertiary))
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isExpanded ? "" : "Inbox")
    }
}

// MARK: - Inbox Category Row

private struct InboxCategoryRow: View {
    let category: InboxCategory
    let isSelected: Bool
    let unreadCount: Int
    let theme: Theme
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Indent marker
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)

                Image(systemName: category.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? theme.accentPrimary : (isHovered ? theme.textSecondary : theme.textTertiary))
                    .frame(width: 16)

                Text(category.displayName)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? theme.textPrimary : (isHovered ? theme.textSecondary : theme.textTertiary))

                Spacer()

                if unreadCount > 0 {
                    Text(unreadCount < 100 ? "\(unreadCount)" : "99+")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected ? theme.accentPrimary : theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(isSelected ? theme.accentPrimary.opacity(0.15) : theme.cardBackground))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? theme.accentPrimary.opacity(0.10) : (isHovered ? theme.hoverBackground : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Generic Folder Item

struct SidebarItemView: View {
    let folder: Folder
    let isSelected: Bool
    let isExpanded: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            if isExpanded { expandedContent } else { collapsedContent }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isExpanded ? "" : folder.rawValue)
    }

    private var expandedContent: some View {
        HStack(spacing: 10) {
            Image(systemName: folder.icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? theme.accentPrimary : (isHovered ? theme.textSecondary : theme.textTertiary))
                .frame(width: 20)

            Text(folder.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? theme.textPrimary : (isHovered ? theme.textSecondary : theme.textTertiary))

            Spacer()

            if folder.count > 0 {
                Text("\(folder.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? theme.accentPrimary : theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(isSelected ? theme.accentPrimary.opacity(0.15) : theme.cardBackground))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? theme.accentPrimary.opacity(0.12) : (isHovered ? theme.hoverBackground : Color.clear))
        )
        .contentShape(Rectangle())
    }

    private var collapsedContent: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 10).fill(theme.accentPrimary.opacity(0.15))
            }
            ZStack(alignment: .topTrailing) {
                Image(systemName: folder.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? theme.accentPrimary : (isHovered ? theme.textSecondary : theme.textTertiary))
                if folder.count > 0 {
                    Circle().fill(theme.accentPrimary).frame(width: 8, height: 8).offset(x: 4, y: -2)
                }
            }
        }
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }
}
