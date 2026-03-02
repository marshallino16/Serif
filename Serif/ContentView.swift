import SwiftUI

struct ContentView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var mailStore = MailStore()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var mailboxViewModel = MailboxViewModel(accountID: "")
    @StateObject private var actionCoordinator: EmailActionCoordinator
    @StateObject private var panelCoordinator = PanelCoordinator()
    @StateObject private var attachmentStore = AttachmentStore(database: .shared)
    @ObservedObject private var subscriptionsStore = SubscriptionsStore.shared
    @State private var selectedAccountID: String?
    @State private var attachmentIndexer: AttachmentIndexer?
    @State private var selectedFolder: Folder = .inbox
    @State private var selectedInboxCategory: InboxCategory? = .all
    @State private var selectedLabel: GmailLabel?
    @State private var selectedEmail: Email?
    @State private var sidebarExpanded = false
    @State private var searchResetTrigger = 0
    @State private var composeMode: ComposeMode = .new
    @AppStorage("undoDuration")        private var undoDuration:        Int = 5
    @AppStorage("refreshInterval")     private var refreshInterval:     Int = 120
    @AppStorage("signatureForNew")     private var signatureForNew:     String = ""
    @AppStorage("signatureForReply")   private var signatureForReply:   String = ""
    @State private var lastRefreshedAt: Date?
    @State private var showEmptyTrashConfirm = false
    @State private var trashTotalCount = 0
    @State private var selectedEmailIDs: Set<String> = []
    @State private var searchFocusTrigger = false

    init() {
        let store = MailStore()
        let vm = MailboxViewModel(accountID: "")
        _mailStore = StateObject(wrappedValue: store)
        _mailboxViewModel = StateObject(wrappedValue: vm)
        _actionCoordinator = StateObject(wrappedValue: EmailActionCoordinator(mailboxViewModel: vm, mailStore: store))
    }

    private var accountID: String {
        selectedAccountID ?? authViewModel.primaryAccount?.id ?? ""
    }

    private var displayedEmails: [Email] {
        if selectedFolder == .drafts { return mailStore.emails(for: .drafts) }
        if selectedFolder == .subscriptions { return subscriptionsStore.entries }
        return mailboxViewModel.emails
    }

    private var listIsLoading: Bool {
        selectedFolder == .subscriptions ? subscriptionsStore.isAnalyzing
        : selectedFolder == .drafts ? mailStore.isLoadingGmailDrafts
        : mailboxViewModel.isLoading
    }

    // MARK: - Body

    var body: some View {
        withLifecycle(
            mainLayout
                .environment(\.theme, themeManager.currentTheme)
                .preferredColorScheme(themeManager.currentTheme.isLight ? .light : .dark)
                .background(themeManager.currentTheme.detailBackground)
                .frame(minWidth: 900, minHeight: 600)
                .toolbar { toolbarContent }
                .alert("Empty Trash", isPresented: $showEmptyTrashConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete All", role: .destructive) {
                        selectedEmail = nil
                        Task { await mailboxViewModel.emptyTrash() }
                    }
                } message: {
                    Text("This will permanently delete \(trashTotalCount) message\(trashTotalCount == 1 ? "" : "s"). This action cannot be undone.")
                }
        )
    }

    // MARK: - Main Layout

    private var mainLayout: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(
                    selectedFolder: $selectedFolder,
                    selectedInboxCategory: $selectedInboxCategory,
                    selectedLabel: $selectedLabel,
                    selectedAccountID: $selectedAccountID,
                    showSettings: $panelCoordinator.showSettings,
                    isExpanded: $sidebarExpanded,
                    showHelp: $panelCoordinator.showHelp,
                    showDebug: $panelCoordinator.showDebug,
                    authViewModel: authViewModel,
                    categoryUnreadCounts: mailboxViewModel.categoryUnreadCounts,
                    userLabels: mailboxViewModel.labels.filter { !$0.isSystemLabel }
                )

                if selectedFolder == .attachments {
                    AttachmentExplorerView(store: attachmentStore)
                } else {
                    ListPaneView(
                        emails: displayedEmails,
                        isLoading: listIsLoading,
                        selectedFolder: $selectedFolder,
                        searchResetTrigger: searchResetTrigger,
                        selectedEmail: $selectedEmail,
                        selectedEmailIDs: $selectedEmailIDs,
                        searchFocusTrigger: $searchFocusTrigger,
                        actionCoordinator: actionCoordinator,
                        mailboxViewModel: mailboxViewModel,
                        onSelectNext: { selectedEmail = $0 },
                        onLoadCurrentFolder: { await loadCurrentFolder() },
                        onEmptyTrashRequested: { count in trashTotalCount = count; showEmptyTrashConfirm = true }
                    )

                    Divider().background(themeManager.currentTheme.divider)

                    DetailPaneView(
                        selectedEmail: selectedEmail,
                        selectedEmailIDs: selectedEmailIDs,
                        selectedFolder: selectedFolder,
                        displayedEmails: displayedEmails,
                        actionCoordinator: actionCoordinator,
                        mailboxViewModel: mailboxViewModel,
                        mailStore: mailStore,
                        accountID: accountID,
                        fromAddress: authViewModel.primaryAccount?.email ?? "",
                        composeMode: composeMode,
                        signatureForNew: signatureForNew,
                        signatureForReply: signatureForReply,
                        panelCoordinator: panelCoordinator,
                        onSelectNext: { selectedEmail = $0 },
                        onClearSelection: { selectedEmail = nil; selectedEmailIDs = [] },
                        onDeselectAll: { selectedEmailIDs = [] },
                        onStartCompose: { mode in startCompose(mode: mode) },
                        onDiscardDraft: { id in discardDraft(id: id) }
                    )
                }
            }

            keyboardShortcuts

            OfflineToastView()
                .environment(\.theme, themeManager.currentTheme)
                .zIndex(4)

            UndoToastView()
                .environment(\.theme, themeManager.currentTheme)
                .zIndex(5)

            SlidePanelsOverlay(
                panels: panelCoordinator,
                themeManager: themeManager,
                authViewModel: authViewModel,
                selectedAccountID: $selectedAccountID,
                undoDuration: $undoDuration,
                refreshInterval: $refreshInterval,
                lastRefreshedAt: lastRefreshedAt,
                signatureForNew: $signatureForNew,
                signatureForReply: $signatureForReply,
                sendAsAliases: mailboxViewModel.sendAsAliases
            )
        }
    }

    // MARK: - Keyboard Shortcuts

    private var keyboardShortcuts: some View {
        Group {
            Button("") { panelCoordinator.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Button("") { panelCoordinator.closeAll() }
                .keyboardShortcut(.escape, modifiers: []).disabled(!panelCoordinator.isAnyOpen)
            Button("") { UndoActionManager.shared.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("") { searchFocusTrigger = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { selectAllEmails() }
                .keyboardShortcut("a", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) { sidebarToggleButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { sidebarToggleButton }
        }

        if !panelCoordinator.isAnyOpen {
            ToolbarItem(placement: .primaryAction) {
                Button { composeNewEmail() } label: {
                    Image(systemName: "square.and.pencil").foregroundColor(themeManager.currentTheme.textPrimary)
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
        .opacity(panelCoordinator.isAnyOpen ? 0 : 1)
        .disabled(panelCoordinator.isAnyOpen)
    }

    // MARK: - Actions

    private func selectAllEmails() {
        selectedEmailIDs = Set(displayedEmails.map { $0.id.uuidString })
        selectedEmail = nil
    }

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
        selectedEmail = nil
    }

    // MARK: - Folder Loading

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
        case .labels:
            if let label = selectedLabel {
                await mailboxViewModel.loadFolder(labelIDs: [label.id])
            }
        case .drafts:
            await mailStore.syncGmailDrafts(accountID: accountID)
        case .subscriptions:
            break
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

    // MARK: - Lifecycle

    private func withLifecycle<V: View>(_ view: V) -> some View {
        view
            .onAppear(perform: handleAppear)
            .onChange(of: selectedFolder, perform: handleFolderChange)
            .onChange(of: selectedInboxCategory, perform: handleCategoryChange)
            .onChange(of: selectedLabel?.id) { _ in handleLabelChange() }
            .onChange(of: selectedAccountID, perform: handleAccountChange)
            .onChange(of: authViewModel.accounts, perform: handleAccountsChange)
            .onChange(of: mailboxViewModel.messages.count) { _ in }
            .onChange(of: selectedEmail, perform: handleSelectedEmailChange)
            .onChange(of: mailboxViewModel.lastRestoredMessageID) { msgID in
                guard let msgID else { return }
                mailboxViewModel.lastRestoredMessageID = nil
                if let restoredEmail = mailboxViewModel.emails.first(where: { $0.gmailMessageID == msgID }) {
                    selectedEmail = restoredEmail
                    selectedEmailIDs = [restoredEmail.id.uuidString]
                }
            }
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
            let indexer = AttachmentIndexer(
                database: .shared,
                messageService: .shared,
                accountID: account.id
            )
            indexer.onProgressUpdate = { [weak attachmentStore] in
                attachmentStore?.refresh()
            }
            attachmentIndexer = indexer
            Task {
                await loadCurrentFolder()
                await mailboxViewModel.loadLabels()
                await mailboxViewModel.loadSendAs()
                await mailboxViewModel.loadCategoryUnreadCounts()
                await GmailProfileService.shared.loadContactPhotos(accountID: account.id)
                lastRefreshedAt = Date()
                // Background: resume pending + discover all attachments from Gmail
                await indexer.resumeAndDiscover()
            }
        } else {
            selectedEmail = mailStore.emails(for: .inbox).first
        }
    }

    private func handleFolderChange(_ folder: Folder) {
        selectedEmail = nil
        selectedEmailIDs = []
        searchResetTrigger += 1
        if folder != .labels { selectedLabel = nil }
        if folder == .attachments {
            attachmentStore.refresh()
        } else if folder == .drafts {
            Task { await mailStore.syncGmailDrafts(accountID: accountID) }
        } else {
            Task { await loadCurrentFolder() }
        }
    }

    private func handleLabelChange() {
        guard selectedFolder == .labels, selectedLabel != nil else { return }
        selectedEmail = nil
        selectedEmailIDs = []
        searchResetTrigger += 1
        Task { await loadCurrentFolder() }
    }

    private func handleCategoryChange(_ category: InboxCategory?) {
        selectedEmail = nil
        selectedEmailIDs = []
        searchResetTrigger += 1
        Task { await loadCurrentFolder() }
    }

    private func handleAccountChange(_ newID: String?) {
        guard let id = newID else { return }
        selectedEmailIDs = []
        let indexer = AttachmentIndexer(
            database: .shared,
            messageService: .shared,
            accountID: id
        )
        indexer.onProgressUpdate = { [weak attachmentStore] in
            attachmentStore?.refresh()
        }
        attachmentIndexer = indexer
        Task {
            await mailboxViewModel.switchAccount(id)
            await loadCurrentFolder()
            await mailboxViewModel.loadLabels()
            await mailboxViewModel.loadSendAs()
            await mailboxViewModel.loadCategoryUnreadCounts()
            await GmailProfileService.shared.loadContactPhotos(accountID: id)
            await indexer.resumeAndDiscover()
        }
    }

    private func handleAccountsChange(_ accounts: [GmailAccount]) {
        if selectedAccountID == nil, let first = accounts.first { selectedAccountID = first.id }
    }

    private func handleSelectedEmailChange(_ email: Email?) {
        guard let email else { return }
        guard let msgID = email.gmailMessageID,
              let message = mailboxViewModel.messages.first(where: { $0.id == msgID }),
              message.isUnread else { return }
        Task {
            await mailboxViewModel.markAsRead(message)
            await mailboxViewModel.loadCategoryUnreadCounts()
        }
    }
}
