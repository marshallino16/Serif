import SwiftUI

struct InboxTab: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.theme) private var theme
    @State private var selectedCategory: InboxCategory = .all
    @State private var selectedEmail: Email?
    @State private var showCompose = false
    @State private var currentFolder: Folder = .inbox
    @State private var selectedLabel: GmailLabel?
    @State private var draftToEdit: Email?
    @State private var showRenameLabelAlert = false
    @State private var showDeleteLabelAlert = false
    @State private var renameLabelText = ""

    private let quickFolders: [Folder] = [.inbox, .starred, .sent, .drafts, .archive, .spam, .trash]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if currentFolder == .inbox || currentFolder == .labels {
                    categoryPicker
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    Divider()
                }

                iOSEmailListView(
                    emails: currentFolder == .drafts
                        ? coordinator.mailStore.emails(for: .drafts)
                        : coordinator.mailboxViewModel.emails,
                    isLoading: currentFolder == .drafts
                        ? coordinator.mailStore.isLoadingGmailDrafts
                        : coordinator.mailboxViewModel.isLoading,
                    selectedEmail: $selectedEmail,
                    onRefresh: {
                        await loadCurrentFolder()
                        if currentFolder == .inbox {
                            await coordinator.mailboxViewModel.loadCategoryUnreadCounts()
                        }
                    },
                    onArchive: currentFolder == .drafts ? nil : { email in
                        coordinator.actionCoordinator.archiveEmail(email) { next in
                            coordinator.selectNext(next)
                        }
                    },
                    onTrash: { email in
                        if currentFolder == .drafts {
                            // Delete draft via Gmail Drafts API
                            Task {
                                if let gid = email.gmailDraftID {
                                    try? await GmailDraftService.shared.deleteDraft(id: gid, accountID: coordinator.accountID)
                                }
                                coordinator.mailStore.deleteDraft(id: email.id)
                                await loadCurrentFolder()
                            }
                        } else {
                            coordinator.actionCoordinator.deleteEmail(email) { next in
                                coordinator.selectNext(next)
                            }
                        }
                    },
                    onToggleRead: currentFolder == .drafts ? nil : { email in
                        if let msgID = email.gmailMessageID {
                            Task {
                                if email.isRead {
                                    await coordinator.mailboxViewModel.markAsUnread(msgID)
                                } else if let msg = coordinator.mailboxViewModel.messages.first(where: { $0.id == msgID }) {
                                    await coordinator.mailboxViewModel.markAsRead(msg)
                                }
                            }
                        }
                    },
                    onToggleStar: currentFolder == .drafts ? nil : { email in
                        if let msgID = email.gmailMessageID {
                            Task { await coordinator.mailboxViewModel.toggleStar(msgID, isStarred: email.isStarred) }
                        }
                    },
                    onLoadMore: {
                        Task { await coordinator.mailboxViewModel.loadMore() }
                    },
                    isLoadingMore: coordinator.mailboxViewModel.isLoadingMore
                )
            }
            .background(theme.listBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(quickFolders) { folder in
                            Button {
                                switchToFolder(folder)
                            } label: {
                                Label(folder.rawValue, systemImage: folder.icon)
                            }
                        }

                        Divider()

                        NavigationLink {
                            iOSTemplateListView(coordinator: coordinator)
                        } label: {
                            Label("Templates", systemImage: "doc.on.doc.fill")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentFolder.rawValue)
                                .font(.system(size: 17, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(theme.textPrimary)
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if currentFolder == .labels, selectedLabel != nil {
                        Menu {
                            Button {
                                renameLabelText = selectedLabel?.name ?? ""
                                showRenameLabelAlert = true
                            } label: {
                                Label("Rename label", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                showDeleteLabelAlert = true
                            } label: {
                                Label("Delete label", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    Button { showCompose = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(item: $selectedEmail) { email in
                iOSEmailDetailView(email: email, coordinator: coordinator)
            }
            .onChange(of: coordinator.pushNavigationEmail) { _, email in
                if let email {
                    selectedEmail = email
                    coordinator.pushNavigationEmail = nil
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            iOSComposeView(
                coordinator: coordinator,
                accountID: coordinator.accountID,
                fromAddress: coordinator.fromAddress,
                mode: .new,
                restoreData: coordinator.pendingSendRestore,
                onDismiss: {
                    showCompose = false
                    coordinator.pendingSendRestore = nil
                }
            )
        }
        .sheet(item: $draftToEdit) { draft in
            iOSComposeView(
                coordinator: coordinator,
                accountID: coordinator.accountID,
                fromAddress: coordinator.fromAddress,
                mode: .new,
                draftEmail: draft,
                onDismiss: {
                    draftToEdit = nil
                    Task { await loadCurrentFolder() }
                }
            )
        }
        .onChange(of: coordinator.showSendRestoreCompose) { _, show in
            if show {
                showCompose = true
                coordinator.showSendRestoreCompose = false
            }
        }
        .onChange(of: selectedEmail) { _, email in
            if currentFolder == .drafts, let email {
                selectedEmail = nil
                draftToEdit = email
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            coordinator.mailboxViewModel.messages = []
            Task { await loadCurrentFolder() }
        }
        .onAppear {
            // Cold launch: pushNavigationEmail may already be set before onChange subscribes
            if let email = coordinator.pushNavigationEmail {
                selectedEmail = email
                coordinator.pushNavigationEmail = nil
            }
            guard !coordinator.mailboxViewModel.accountID.isEmpty else { return }
            Task { await loadCurrentFolder() }
        }
        .onChange(of: currentFolder) { oldFolder, newFolder in
            if newFolder != .labels { selectedLabel = nil }
            // Don't clear mailboxViewModel when switching to/from drafts
            // (drafts use mailStore, not mailboxViewModel)
            if newFolder != .drafts && oldFolder != .drafts {
                coordinator.mailboxViewModel.messages = []
            }
            if newFolder != .labels {
                Task { await loadCurrentFolder() }
            }
        }
        .onChange(of: selectedLabel) { _, label in
            guard let label else { return }
            currentFolder = .labels
            coordinator.mailboxViewModel.messages = []
            Task {
                await coordinator.mailboxViewModel.refreshCurrentFolder(labelIDs: [label.id])
            }
        }
        .alert("Rename Label", isPresented: $showRenameLabelAlert) {
            TextField("Label name", text: $renameLabelText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let newName = renameLabelText.trimmingCharacters(in: .whitespaces)
                guard let label = selectedLabel,
                      !newName.isEmpty,
                      newName != label.name else { return }
                Task {
                    await coordinator.mailboxViewModel.renameLabel(label, to: newName)
                    if let updated = coordinator.mailboxViewModel.labels.first(where: { $0.id == label.id }) {
                        selectedLabel = updated
                    }
                }
            }
        } message: {
            Text("Enter a new name for this label.")
        }
        .alert("Delete Label", isPresented: $showDeleteLabelAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let label = selectedLabel else { return }
                Task {
                    await coordinator.mailboxViewModel.deleteLabel(label)
                    selectedLabel = nil
                    currentFolder = .inbox
                }
            }
        } message: {
            Text("Are you sure? This will remove the label from all messages.")
        }
    }

    // MARK: - Folder Switching

    private func switchToFolder(_ folder: Folder) {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentFolder = folder
        }
    }

    private func loadCurrentFolder() async {
        if currentFolder == .drafts {
            await coordinator.mailStore.syncGmailDrafts(accountID: coordinator.accountID)
        } else if currentFolder == .inbox {
            await coordinator.mailboxViewModel.refreshCurrentFolder(
                labelIDs: selectedCategory.gmailLabelIDs
            )
        } else if let labelID = currentFolder.gmailLabelID {
            await coordinator.mailboxViewModel.refreshCurrentFolder(labelIDs: [labelID])
        } else if let query = currentFolder.gmailQuery {
            await coordinator.mailboxViewModel.loadFolder(labelIDs: [], query: query)
        }
    }

    // MARK: - Category Picker

    private var userLabels: [GmailLabel] {
        coordinator.mailboxViewModel.labels.filter { !$0.isSystemLabel }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Labels dropdown
                if !userLabels.isEmpty {
                    Menu {
                        ForEach(userLabels) { label in
                            Button {
                                // Switch to label view
                                selectedLabel = label
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: label.color?.backgroundColor ?? "#888888"))
                                        .frame(width: 8, height: 8)
                                    Text(label.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 11))
                            if let label = selectedLabel {
                                Text(label.name)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            selectedLabel != nil
                                ? theme.accentPrimary.opacity(0.15)
                                : theme.cardBackground
                        )
                        .foregroundColor(
                            selectedLabel != nil
                                ? theme.accentPrimary
                                : theme.textSecondary
                        )
                        .clipShape(Capsule())
                    }
                }

                if currentFolder == .inbox {
                    ForEach(InboxCategory.allCases) { category in
                        let unreadCount = coordinator.mailboxViewModel.categoryUnreadCounts[category] ?? 0
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = category
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(category.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                if unreadCount > 0 && selectedCategory != category {
                                    Text("\(unreadCount)")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selectedCategory == category
                                    ? theme.accentPrimary
                                    : theme.cardBackground
                            )
                            .foregroundColor(
                                selectedCategory == category
                                    ? theme.textInverse
                                    : theme.textSecondary
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
