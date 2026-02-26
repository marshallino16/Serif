import SwiftUI

struct ContentView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var mailStore = MailStore()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var mailboxViewModel = MailboxViewModel(accountID: "")
    @State private var selectedAccountID: String?
    @State private var selectedFolder: Folder = .inbox
    @State private var selectedInboxCategory: InboxCategory? = .all
    @State private var selectedEmail: Email?
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showDebug = false
    @State private var sidebarExpanded = false
    @State private var searchResetTrigger = 0
    @State private var composeMode: ComposeMode = .new
    @State private var showAttachmentPreview = false
    @State private var attachmentPreviewData: Data?
    @State private var attachmentPreviewName = ""
    @State private var attachmentPreviewFileType: Attachment.FileType = .document
    @AppStorage("undoDuration")      private var undoDuration:      Int = 5
    @AppStorage("refreshInterval")   private var refreshInterval:   Int = 120
    @State private var lastRefreshedAt: Date?

    private var isEditingDraft: Bool {
        guard let email = selectedEmail else { return false }
        return email.isDraft
    }

    private var isPanelOpen: Bool { showSettings || showHelp || showDebug || showAttachmentPreview }

    private func closePanel() {
        showSettings = false
        showHelp = false
        showDebug = false
        showAttachmentPreview = false
    }

    // MARK: - Email source

    private var displayedEmails: [Email] {
        if selectedFolder == .drafts {
            return mailStore.emails(for: .drafts)
        }
        return mailboxViewModel.emails
    }

    var body: some View {
        withLifecycle(
            mainLayout
                .environment(\.theme, themeManager.currentTheme)
                .background(themeManager.currentTheme.detailBackground)
                .frame(minWidth: 900, minHeight: 600)
                .toolbar { toolbarContent }
        )
    }

    private func withLifecycle<V: View>(_ view: V) -> some View {
        view
            .onAppear(perform: handleAppear)
            .onChange(of: selectedFolder, perform: handleFolderChange)
            .onChange(of: selectedInboxCategory, perform: handleCategoryChange)
            .onChange(of: selectedAccountID, perform: handleAccountChange)
            .onChange(of: authViewModel.accounts, perform: handleAccountsChange)
            .onChange(of: mailboxViewModel.messages.count, perform: handleMessagesCountChange)
            .onChange(of: selectedEmail, perform: handleSelectedEmailChange)
            .onReceive(Timer.publish(every: TimeInterval(refreshInterval), on: .main, in: .common).autoconnect()) { _ in
                guard !mailboxViewModel.isLoading, !mailboxViewModel.accountID.isEmpty else { return }
                lastRefreshedAt = Date()
                Task {
                    await loadCurrentFolder()
                    await mailboxViewModel.loadCategoryUnreadCounts()
                }
            }
    }

    private func handleAppear() {
        if let account = authViewModel.primaryAccount {
            selectedAccountID = account.id
            mailboxViewModel.accountID = account.id
            Task {
                await loadCurrentFolder()
                await mailboxViewModel.loadLabels()
                await mailboxViewModel.loadCategoryUnreadCounts()
                await GmailProfileService.shared.loadContactPhotos(accountID: account.id)
                lastRefreshedAt = Date()
            }
        } else {
            selectedEmail = mailStore.emails(for: .inbox).first
        }
    }

    private func handleFolderChange(_ folder: Folder) {
        selectedEmail = nil
        searchResetTrigger += 1
        if folder != .drafts { Task { await loadCurrentFolder() } }
    }

    private func handleCategoryChange(_ category: InboxCategory?) {
        selectedEmail = nil
        searchResetTrigger += 1
        Task { await loadCurrentFolder() }
    }

    private func handleAccountChange(_ newID: String?) {
        guard let id = newID else { return }
        Task {
            await mailboxViewModel.switchAccount(id)
            await loadCurrentFolder()
            await mailboxViewModel.loadLabels()
            await mailboxViewModel.loadCategoryUnreadCounts()
            await GmailProfileService.shared.loadContactPhotos(accountID: id)
        }
    }

    private func handleAccountsChange(_ accounts: [GmailAccount]) {
        if selectedAccountID == nil, let first = accounts.first { selectedAccountID = first.id }
    }

    private func handleMessagesCountChange(_ count: Int) {
        guard selectedEmail == nil else { return }
        guard selectedFolder != .trash, selectedFolder != .spam else { return }
        let first = mailboxViewModel.emails.first
        selectedEmail = first
        if let first { markAsReadIfNeeded(first) }
    }

    private func handleSelectedEmailChange(_ email: Email?) {
        guard let email else { return }
        markAsReadIfNeeded(email)
    }

    private func markAsReadIfNeeded(_ email: Email) {
        guard let msgID = email.gmailMessageID,
              let message = mailboxViewModel.messages.first(where: { $0.id == msgID }),
              message.isUnread else { return }
        Task {
            await mailboxViewModel.markAsRead(message)
            await mailboxViewModel.loadCategoryUnreadCounts()
        }
    }

    private var mainLayout: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(
                    selectedFolder: $selectedFolder,
                    selectedInboxCategory: $selectedInboxCategory,
                    selectedAccountID: $selectedAccountID,
                    showSettings: $showSettings,
                    isExpanded: $sidebarExpanded,
                    showHelp: $showHelp,
                    showDebug: $showDebug,
                    authViewModel: authViewModel,
                    categoryUnreadCounts: mailboxViewModel.categoryUnreadCounts
                )
                listPane
                Divider().background(themeManager.currentTheme.divider)
                detailPane.frame(minWidth: 400)
            }

            Button("") { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showSettings = true } }
                .keyboardShortcut(",", modifiers: .command).frame(width: 0, height: 0).opacity(0)

            Button("") { closePanel() }
                .keyboardShortcut(.escape, modifiers: []).frame(width: 0, height: 0).opacity(0).disabled(!isPanelOpen)

            UndoToastView()
                .environment(\.theme, themeManager.currentTheme)
                .zIndex(5)

            slidePanels
        }
    }

    private var behaviorSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Behavior")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.textPrimary)

            HStack {
                Text("Undo duration")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.currentTheme.textSecondary)
                Spacer()
                Picker("", selection: $undoDuration) {
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("20s").tag(20)
                    Text("30s").tag(30)
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }

            Divider().background(themeManager.currentTheme.divider)

            HStack {
                Text("Refresh interval")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.currentTheme.textSecondary)
                Spacer()
                Picker("", selection: $refreshInterval) {
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                    Text("10 min").tag(600)
                    Text("1 hour").tag(3600)
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }

            RefreshStatusView(lastRefreshedAt: lastRefreshedAt, refreshInterval: refreshInterval)
        }
        .padding(20)
        .background(themeManager.currentTheme.cardBackground)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var slidePanels: some View {
        SlidePanel(isPresented: $showSettings, title: "Settings") {
            VStack(alignment: .leading, spacing: 16) {
                ThemePickerView(themeManager: themeManager)
                AccountsSettingsView(authViewModel: authViewModel, selectedAccountID: $selectedAccountID)
                behaviorSettingsCard
            }
            .padding(20)
        }
        .environment(\.theme, themeManager.currentTheme)
        .zIndex(10)

        SlidePanel(isPresented: $showHelp, title: "Keyboard Shortcuts") {
            ShortcutsHelpView()
        }
        .environment(\.theme, themeManager.currentTheme)
        .zIndex(10)

        #if DEBUG
        SlidePanel(isPresented: $showDebug, title: "Debug") {
            DebugMenuView()
        }
        .environment(\.theme, themeManager.currentTheme)
        .zIndex(10)
        #endif

        SlidePanel(isPresented: $showAttachmentPreview, title: attachmentPreviewName, scrollable: false) {
            if let data = attachmentPreviewData {
                AttachmentPreviewView(
                    data: data,
                    fileName: attachmentPreviewName,
                    fileType: attachmentPreviewFileType,
                    onDownload: { saveAttachment(data: data, name: attachmentPreviewName) },
                    onClose: { showAttachmentPreview = false }
                )
            } else {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(themeManager.currentTheme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.theme, themeManager.currentTheme)
        .zIndex(10)
    }

    private func saveAttachment(data: Data, name: String) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) { sidebarToggleButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { sidebarToggleButton }
        }

        if !isPanelOpen {
            ToolbarItem(placement: .primaryAction) {
                Button { composeNewEmail() } label: {
                    Image(systemName: "square.and.pencil").foregroundColor(.white)
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Compose (⌘N)")
            }
        }
    }

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { sidebarExpanded.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(themeManager.currentTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .help("Toggle sidebar")
        .opacity(isPanelOpen ? 0 : 1)
        .disabled(isPanelOpen)
    }

    // MARK: - List pane

    @ViewBuilder
    private var listPane: some View {
        if selectedFolder == .attachments {
            AttachmentsListView(
                mailboxViewModel: mailboxViewModel,
                selectedEmail: $selectedEmail
            )
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        } else {
            EmailListView(
                emails: displayedEmails,
                isLoading: selectedFolder != .drafts && mailboxViewModel.isLoading,
                onLoadMore: { Task { await mailboxViewModel.loadMore() } },
                onSearch: { query in
                    if query.isEmpty {
                        Task { await loadCurrentFolder() }
                    } else {
                        Task { await mailboxViewModel.search(query: query) }
                    }
                },
                onArchive:    { archiveEmail($0) },
                onDelete:     { deleteEmail($0) },
                onToggleStar: { toggleStarEmail($0) },
                onMarkUnread: { markUnreadEmail($0) },
                onMarkSpam:   { markSpamEmail($0) },
                searchResetTrigger: searchResetTrigger,
                selectedEmail: $selectedEmail,
                selectedFolder: $selectedFolder
            )
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if isEditingDraft, let draftId = selectedEmail?.id {
            ComposeView(
                mailStore: mailStore,
                draftId: draftId,
                accountID: selectedAccountID ?? authViewModel.primaryAccount?.id ?? "",
                fromAddress: authViewModel.primaryAccount?.email ?? "",
                mode: composeMode,
                onDiscard: { discardDraft(id: draftId) }
            )
            .id(draftId)
        } else if let email = selectedEmail {
            EmailDetailView(
                email: email,
                accountID: selectedAccountID ?? authViewModel.primaryAccount?.id ?? "",
                onArchive:    { archiveEmail(email) },
                onDelete:     { deleteEmail(email) },
                onToggleStar: { toggleStarEmail(email) },
                onMarkUnread: { markUnreadEmail(email) },
                allLabels:    mailboxViewModel.labels,
                onAddLabel:   { labelID in
                    guard let msgID = email.gmailMessageID else { return }
                    Task { await mailboxViewModel.addLabel(labelID, to: msgID) }
                },
                onRemoveLabel: { labelID in
                    guard let msgID = email.gmailMessageID else { return }
                    Task { await mailboxViewModel.removeLabel(labelID, from: msgID) }
                },
                onReply:             { mode in startCompose(mode: mode) },
                onReplyAll:          { mode in startCompose(mode: mode) },
                onForward:           { mode in startCompose(mode: mode) },
                onPreviewAttachment: { data, name, fileType in
                    attachmentPreviewData     = data
                    attachmentPreviewName     = name
                    attachmentPreviewFileType = fileType
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showAttachmentPreview = true
                    }
                }
            )
            .id(email.id)
        } else {
            emptyState
        }
    }

    // MARK: - Folder loading

    private func loadCurrentFolder() async {
        guard !mailboxViewModel.accountID.isEmpty else { return }
        switch selectedFolder {
        case .inbox:
            if let category = selectedInboxCategory {
                if category == .all {
                    await mailboxViewModel.loadFolder(labelIDs: ["INBOX"])
                } else {
                    await mailboxViewModel.loadFolder(labelIDs: category.gmailLabelIDs)
                }
            } else {
                await mailboxViewModel.loadFolder(labelIDs: ["INBOX"])
            }
        case .drafts:
            break  // local only
        case .attachments:
            await mailboxViewModel.loadFolder(labelIDs: [], query: "has:attachment")
        default:
            if let labelID = selectedFolder.gmailLabelID {
                await mailboxViewModel.loadFolder(labelIDs: [labelID])
            } else if let query = selectedFolder.gmailQuery {
                await mailboxViewModel.loadFolder(labelIDs: [], query: query)
            }
        }
    }

    // MARK: - Email actions

    private func archiveEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        Task {
            await mailboxViewModel.archive(msgID)
            selectedEmail = mailboxViewModel.emails.first
        }
    }

    private func deleteEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        Task {
            await mailboxViewModel.trash(msgID)
            selectedEmail = mailboxViewModel.emails.first
        }
    }

    private func toggleStarEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        Task { await mailboxViewModel.toggleStar(msgID, isStarred: email.isStarred) }
    }

    private func markUnreadEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        Task { await mailboxViewModel.markAsUnread(msgID) }
    }

    private func markSpamEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        Task {
            await mailboxViewModel.spam(msgID)
            selectedEmail = mailboxViewModel.emails.first
        }
    }

    // MARK: - Compose

    private func composeNewEmail() {
        composeMode = .new
        let draft = mailStore.createDraft()
        selectedFolder = .drafts
        selectedEmail = draft
    }

    private func startCompose(mode: ComposeMode) {
        composeMode = mode
        let draft = mailStore.createDraft()
        selectedFolder = .drafts
        selectedEmail = draft
    }

    private func discardDraft(id: UUID) {
        composeMode = .new
        mailStore.deleteDraft(id: id)
        selectedEmail = mailStore.emails(for: selectedFolder).first
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.open")
                .font(.system(size: 40))
                .foregroundColor(themeManager.currentTheme.textTertiary)
            Text("Select an email to read")
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.currentTheme.detailBackground)
    }
}

// MARK: - Refresh Status

private struct RefreshStatusView: View {
    let lastRefreshedAt: Date?
    let refreshInterval: Int
    @State private var now: Date = Date()
    @Environment(\.theme) private var theme

    private var timer: Timer.TimerPublisher {
        Timer.publish(every: 1, on: .main, in: .common)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
                Text(lastRefreshLabel)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
                Spacer()
            }
            HStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
                Text(nextRefreshLabel)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
                Spacer()
            }
        }
        .onReceive(timer.autoconnect()) { date in now = date }
    }

    private var lastRefreshLabel: String {
        guard let last = lastRefreshedAt else { return "Last refresh: never" }
        let elapsed = Int(now.timeIntervalSince(last))
        if elapsed < 60 { return "Last refresh: \(elapsed)s ago" }
        let mins = elapsed / 60
        return "Last refresh: \(mins) min ago"
    }

    private var nextRefreshLabel: String {
        guard let last = lastRefreshedAt else { return "Next refresh: soon" }
        let elapsed = now.timeIntervalSince(last)
        let remaining = max(0, Double(refreshInterval) - elapsed)
        let secs = Int(remaining)
        if secs < 60 { return "Next refresh: in \(secs)s" }
        let mins = secs / 60
        let rem  = secs % 60
        return rem > 0 ? "Next refresh: in \(mins)m \(rem)s" : "Next refresh: in \(mins)m"
    }
}
