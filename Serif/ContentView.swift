import SwiftUI

struct ContentView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var coordinator = AppCoordinator()

    // MARK: - Body

    var body: some View {
        withLifecycle(
            mainLayout
                .environment(\.theme, themeManager.currentTheme)
                .preferredColorScheme(themeManager.currentTheme.isLight ? .light : .dark)
                .background(themeManager.currentTheme.detailBackground)
                .frame(minWidth: 900, minHeight: 600)
                .toolbar { toolbarContent }
                .alert("Empty Trash", isPresented: $coordinator.showEmptyTrashConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete All", role: .destructive) {
                        coordinator.selectedEmail = nil
                        Task { await coordinator.mailboxViewModel.emptyTrash() }
                    }
                } message: {
                    Text("This will permanently delete \(coordinator.trashTotalCount) message\(coordinator.trashTotalCount == 1 ? "" : "s"). This action cannot be undone.")
                }
                .alert("Empty Spam", isPresented: $coordinator.showEmptySpamConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete All", role: .destructive) {
                        coordinator.selectedEmail = nil
                        Task { await coordinator.mailboxViewModel.emptySpam() }
                    }
                } message: {
                    Text("This will permanently delete \(coordinator.spamTotalCount) spam message\(coordinator.spamTotalCount == 1 ? "" : "s"). This action cannot be undone.")
                }
        )
    }

    // MARK: - Main Layout

    private var mainLayout: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(
                    selectedFolder: $coordinator.selectedFolder,
                    selectedInboxCategory: $coordinator.selectedInboxCategory,
                    selectedLabel: $coordinator.selectedLabel,
                    selectedAccountID: $coordinator.selectedAccountID,
                    showSettings: panelBinding(\.showSettings),
                    isExpanded: $coordinator.sidebarExpanded,
                    showHelp: panelBinding(\.showHelp),
                    showDebug: panelBinding(\.showDebug),
                    authViewModel: coordinator.authViewModel,
                    categoryUnreadCounts: coordinator.mailboxViewModel.categoryUnreadCounts,
                    userLabels: coordinator.mailboxViewModel.labels.filter { !$0.isSystemLabel },
                    onRenameLabel: { label, newName in Task { await coordinator.renameLabel(label, to: newName) } },
                    onDeleteLabel: { label in Task { await coordinator.deleteLabel(label) } }
                )

                if coordinator.selectedFolder == .attachments {
                    AttachmentExplorerView(store: coordinator.attachmentStore, panelCoordinator: coordinator.panelCoordinator, accountID: coordinator.accountID)
                } else {
                    ListPaneView(
                        emails: coordinator.displayedEmails,
                        isLoading: coordinator.listIsLoading,
                        selectedFolder: $coordinator.selectedFolder,
                        searchResetTrigger: coordinator.searchResetTrigger,
                        selectedEmail: $coordinator.selectedEmail,
                        selectedEmailIDs: $coordinator.selectedEmailIDs,
                        searchFocusTrigger: $coordinator.searchFocusTrigger,
                        coordinator: coordinator
                    )

                    DetailPaneView(
                        selectedEmail: coordinator.selectedEmail,
                        selectedEmailIDs: coordinator.selectedEmailIDs,
                        selectedFolder: coordinator.selectedFolder,
                        displayedEmails: coordinator.displayedEmails,
                        coordinator: coordinator
                    )
                }
            }

            KeyboardShortcutsView(coordinator: coordinator)

            OfflineToastView()
                .environment(\.theme, themeManager.currentTheme)
                .zIndex(4)

            UndoToastView()
                .environment(\.theme, themeManager.currentTheme)
                .zIndex(5)

            ToastOverlayView()
                .environment(\.theme, themeManager.currentTheme)
                .zIndex(6)

            SlidePanelsOverlay(
                panels: coordinator.panelCoordinator,
                themeManager: themeManager,
                authViewModel: coordinator.authViewModel,
                selectedAccountID: $coordinator.selectedAccountID,
                undoDuration: $coordinator.undoDuration,
                refreshInterval: $coordinator.refreshInterval,
                lastRefreshedAt: coordinator.lastRefreshedAt,
                signatureForNew: $coordinator.signatureForNew,
                signatureForReply: $coordinator.signatureForReply,
                sendAsAliases: coordinator.mailboxViewModel.sendAsAliases,
                attachmentStore: coordinator.attachmentStore
            )
        }
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

        if !coordinator.panelCoordinator.isAnyOpen {
            ToolbarItem(placement: .primaryAction) {
                Button { coordinator.composeNewEmail() } label: {
                    Image(systemName: "square.and.pencil").foregroundColor(themeManager.currentTheme.textPrimary)
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Compose (\u{2318}N)")
            }
        }
    }

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { coordinator.sidebarExpanded.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(themeManager.currentTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .help("Toggle sidebar")
        .opacity(coordinator.panelCoordinator.isAnyOpen ? 0 : 1)
        .disabled(coordinator.panelCoordinator.isAnyOpen)
    }

    // MARK: - Lifecycle

    private func withLifecycle<V: View>(_ view: V) -> some View {
        view
            .onAppear(perform: coordinator.handleAppear)
            .onChange(of: coordinator.selectedFolder, perform: coordinator.handleFolderChange)
            .onChange(of: coordinator.selectedInboxCategory, perform: coordinator.handleCategoryChange)
            .onChange(of: coordinator.selectedLabel?.id) { _ in coordinator.handleLabelChange() }
            .onChange(of: coordinator.selectedAccountID, perform: coordinator.handleAccountChange)
            .onChange(of: coordinator.authViewModel.accounts, perform: coordinator.handleAccountsChange)
            .onChange(of: coordinator.mailboxViewModel.messages.count) { _ in }
            .onChange(of: coordinator.selectedEmail, perform: coordinator.handleSelectedEmailChange)
            .onChange(of: coordinator.signatureForNew) { _ in if !coordinator.accountID.isEmpty { coordinator.saveSignatures(for: coordinator.accountID) } }
            .onChange(of: coordinator.signatureForReply) { _ in if !coordinator.accountID.isEmpty { coordinator.saveSignatures(for: coordinator.accountID) } }
            .onChange(of: coordinator.mailboxViewModel.lastRestoredMessageID) { msgID in
                guard let msgID else { return }
                coordinator.mailboxViewModel.lastRestoredMessageID = nil
                if let restoredEmail = coordinator.mailboxViewModel.emails.first(where: { $0.gmailMessageID == msgID }) {
                    coordinator.selectedEmail = restoredEmail
                    coordinator.selectedEmailIDs = [restoredEmail.id.uuidString]
                }
            }
            .onReceive(Timer.publish(every: TimeInterval(coordinator.refreshInterval), on: .main, in: .common).autoconnect()) { _ in
                guard !coordinator.mailboxViewModel.isLoading, !coordinator.mailboxViewModel.accountID.isEmpty else { return }
                coordinator.lastRefreshedAt = Date()
                Task {
                    await coordinator.loadCurrentFolder()
                    await coordinator.mailboxViewModel.loadCategoryUnreadCounts()
                }
            }
    }

    // MARK: - Helpers

    private func panelBinding(_ keyPath: ReferenceWritableKeyPath<PanelCoordinator, Bool>) -> Binding<Bool> {
        Binding(
            get: { coordinator.panelCoordinator[keyPath: keyPath] },
            set: { coordinator.panelCoordinator[keyPath: keyPath] = $0 }
        )
    }
}
