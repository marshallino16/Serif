import SwiftUI

struct ContentView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var mailStore = MailStore()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var mailboxViewModel = MailboxViewModel(accountID: "")
    @ObservedObject private var subscriptionsStore = SubscriptionsStore.shared
    @State private var selectedAccountID: String?
    @State private var selectedFolder: Folder = .inbox
    @State private var selectedInboxCategory: InboxCategory? = .all
    @State private var selectedLabel: GmailLabel?
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
    @State private var showOriginal = false
    @State private var originalMessage: GmailMessage?
    @State private var originalRawSource: String?
    @State private var isLoadingOriginal = false
    @AppStorage("undoDuration")        private var undoDuration:        Int = 5
    @AppStorage("refreshInterval")     private var refreshInterval:     Int = 120
    @AppStorage("signatureForNew")     private var signatureForNew:     String = ""
    @AppStorage("signatureForReply")   private var signatureForReply:   String = ""
    @State private var lastRefreshedAt: Date?
    @State private var showEmptyTrashConfirm = false
    @State private var trashTotalCount = 0

    private var isEditingDraft: Bool {
        guard let email = selectedEmail else { return false }
        return email.isDraft
    }

    private var isPanelOpen: Bool { showSettings || showHelp || showDebug || showAttachmentPreview || showOriginal }

    private func closePanel() {
        showSettings = false
        showHelp = false
        showDebug = false
        showAttachmentPreview = false
        showOriginal = false
    }

    // MARK: - Email source

    private var displayedEmails: [Email] {
        if selectedFolder == .drafts {
            return mailStore.emails(for: .drafts)
        }
        if selectedFolder == .subscriptions {
            return subscriptionsStore.entries
        }
        return mailboxViewModel.emails
    }

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

    private func withLifecycle<V: View>(_ view: V) -> some View {
        view
            .onAppear(perform: handleAppear)
            .onChange(of: selectedFolder, perform: handleFolderChange)
            .onChange(of: selectedInboxCategory, perform: handleCategoryChange)
            .onChange(of: selectedLabel?.id) { _ in handleLabelChange() }
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
                await mailboxViewModel.loadSendAs()
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
        if folder != .labels { selectedLabel = nil }
        if folder != .drafts { Task { await loadCurrentFolder() } }
    }

    private func handleLabelChange() {
        guard selectedFolder == .labels, selectedLabel != nil else { return }
        selectedEmail = nil
        searchResetTrigger += 1
        Task { await loadCurrentFolder() }
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
            await mailboxViewModel.loadSendAs()
            await mailboxViewModel.loadCategoryUnreadCounts()
            await GmailProfileService.shared.loadContactPhotos(accountID: id)
        }
    }

    private func handleAccountsChange(_ accounts: [GmailAccount]) {
        if selectedAccountID == nil, let first = accounts.first { selectedAccountID = first.id }
    }

    private func handleMessagesCountChange(_ count: Int) {
        // Don't auto-select — the detail pane stays empty until the user clicks
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
                    selectedLabel: $selectedLabel,
                    selectedAccountID: $selectedAccountID,
                    showSettings: $showSettings,
                    isExpanded: $sidebarExpanded,
                    showHelp: $showHelp,
                    showDebug: $showDebug,
                    authViewModel: authViewModel,
                    categoryUnreadCounts: mailboxViewModel.categoryUnreadCounts,
                    userLabels: mailboxViewModel.labels.filter { !$0.isSystemLabel }
                )
                listPane
                Divider().background(themeManager.currentTheme.divider)
                detailPane.frame(minWidth: 400)
            }

            Button("") { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showSettings = true } }
                .keyboardShortcut(",", modifiers: .command).frame(width: 0, height: 0).opacity(0)

            Button("") { closePanel() }
                .keyboardShortcut(.escape, modifiers: []).frame(width: 0, height: 0).opacity(0).disabled(!isPanelOpen)

            OfflineToastView()
                .environment(\.theme, themeManager.currentTheme)
                .zIndex(4)

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
        .shadow(color: .black.opacity(themeManager.currentTheme.isLight ? 0.06 : 0), radius: 8, y: 2)
    }

    @State private var isRefreshingContacts = false

    private var contactsSettingsCard: some View {
        let acctID = selectedAccountID ?? authViewModel.primaryAccount?.id ?? ""
        let count = ContactStore.shared.contacts(for: acctID).count

        return VStack(alignment: .leading, spacing: 12) {
            Text("Contacts")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.textPrimary)

            HStack {
                Text("\(count) contacts cached")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.currentTheme.textSecondary)

                Spacer()

                Button {
                    guard !isRefreshingContacts else { return }
                    isRefreshingContacts = true
                    Task {
                        await GmailProfileService.shared.refreshContacts(accountID: acctID)
                        isRefreshingContacts = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isRefreshingContacts {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        Text(isRefreshingContacts ? "Refreshing…" : "Refresh")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(themeManager.currentTheme.accentPrimary)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingContacts)
            }
        }
        .padding(20)
        .background(themeManager.currentTheme.cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(themeManager.currentTheme.isLight ? 0.06 : 0), radius: 8, y: 2)
    }

    private var signatureSettingsCard: some View {
        let aliases = mailboxViewModel.sendAsAliases
        let defaultEmail = aliases.first(where: { $0.isPrimary == true })?.sendAsEmail
            ?? aliases.first?.sendAsEmail ?? ""

        return VStack(alignment: .leading, spacing: 12) {
            Text("Signatures")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.textPrimary)

            if aliases.isEmpty {
                Text("No aliases found")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.currentTheme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(aliases, id: \.sendAsEmail) { alias in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(alias.displayName ?? alias.sendAsEmail)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(themeManager.currentTheme.textPrimary)
                                if alias.isPrimary == true {
                                    Text("Primary")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(themeManager.currentTheme.accentPrimary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(themeManager.currentTheme.accentPrimary.opacity(0.15)))
                                }
                            }
                            Text(alias.sendAsEmail)
                                .font(.system(size: 11))
                                .foregroundColor(themeManager.currentTheme.textTertiary)
                            if let sig = alias.signature, !sig.isEmpty {
                                Text(sig.strippingHTML.prefix(80) + (sig.strippingHTML.count > 80 ? "…" : ""))
                                    .font(.system(size: 10))
                                    .foregroundColor(themeManager.currentTheme.textTertiary)
                                    .lineLimit(2)
                            } else {
                                Text("No signature")
                                    .font(.system(size: 10))
                                    .foregroundColor(themeManager.currentTheme.textTertiary)
                                    .italic()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider().background(themeManager.currentTheme.divider)

                HStack {
                    Text("New emails")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.currentTheme.textSecondary)
                    Spacer()
                    Picker("", selection: $signatureForNew) {
                        Text("Default").tag("")
                        ForEach(aliases, id: \.sendAsEmail) { alias in
                            Text(alias.displayName ?? alias.sendAsEmail).tag(alias.sendAsEmail)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                HStack {
                    Text("Replies & forwards")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.currentTheme.textSecondary)
                    Spacer()
                    Picker("", selection: $signatureForReply) {
                        Text("Default").tag("")
                        ForEach(aliases, id: \.sendAsEmail) { alias in
                            Text(alias.displayName ?? alias.sendAsEmail).tag(alias.sendAsEmail)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
            }
        }
        .padding(20)
        .background(themeManager.currentTheme.cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(themeManager.currentTheme.isLight ? 0.06 : 0), radius: 8, y: 2)
    }

    @ViewBuilder
    private var slidePanels: some View {
        SlidePanel(isPresented: $showSettings, title: "Settings") {
            VStack(alignment: .leading, spacing: 16) {
                ThemePickerView(themeManager: themeManager)
                AccountsSettingsView(authViewModel: authViewModel, selectedAccountID: $selectedAccountID)
                behaviorSettingsCard
                contactsSettingsCard
                signatureSettingsCard
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

        SlidePanel(isPresented: $showOriginal, title: "Original Message") {
            if let msg = originalMessage {
                OriginalMessageView(
                    message: msg,
                    rawSource: originalRawSource,
                    isLoading: isLoadingOriginal
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
                    Image(systemName: "square.and.pencil").foregroundColor(themeManager.currentTheme.accentPrimary)
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
                isLoading: selectedFolder == .subscriptions ? subscriptionsStore.isAnalyzing
                         : selectedFolder != .drafts && mailboxViewModel.isLoading,
                onLoadMore: { Task { await mailboxViewModel.loadMore() } },
                onSearch: { query in
                    if query.isEmpty {
                        Task { await loadCurrentFolder() }
                    } else {
                        Task { await mailboxViewModel.search(query: query) }
                    }
                },
                onArchive:      { archiveEmail($0) },
                onDelete:       { deleteEmail($0) },
                onToggleStar:   { toggleStarEmail($0) },
                onMarkUnread:   { markUnreadEmail($0) },
                onMarkSpam:          { markSpamEmail($0) },
                onUnsubscribe:       { unsubscribeEmail($0) },
                onMoveToInbox:       { moveToInboxEmail($0) },
                onDeletePermanently: { deletePermanentlyEmail($0) },
                onMarkNotSpam:       { markNotSpamEmail($0) },
                onEmptyTrash:        { emptyTrash() },
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
                sendAsAliases: mailboxViewModel.sendAsAliases,
                signatureForNew: signatureForNew,
                signatureForReply: signatureForReply,
                contacts: ContactStore.shared.contacts(for: selectedAccountID ?? authViewModel.primaryAccount?.id ?? ""),
                onDiscard: { discardDraft(id: draftId) }
            )
            .id(draftId)
        } else if let email = selectedEmail {
            EmailDetailView(
                email: email,
                accountID: selectedAccountID ?? authViewModel.primaryAccount?.id ?? "",
                onArchive:           selectedFolder == .archive ? nil : { archiveEmail(email) },
                onDelete:            selectedFolder == .trash   ? nil : { deleteEmail(email) },
                onMoveToInbox:       selectedFolder == .archive || selectedFolder == .trash ? { moveToInboxEmail(email) } : nil,
                onDeletePermanently: selectedFolder == .trash ? { deletePermanentlyEmail(email) } : nil,
                onMarkNotSpam:       selectedFolder == .spam ? { markNotSpamEmail(email) } : nil,
                onToggleStar: { isCurrentlyStarred in
                    guard let msgID = email.gmailMessageID else { return }
                    Task { await mailboxViewModel.toggleStar(msgID, isStarred: isCurrentlyStarred) }
                },
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
                onCreateAndAddLabel: { name, completion in
                    guard let msgID = email.gmailMessageID else { completion(nil); return }
                    Task {
                        let labelID = await mailboxViewModel.createAndAddLabel(name: name, to: msgID)
                        completion(labelID)
                    }
                },
                onPreviewAttachment: { data, name, fileType in
                    attachmentPreviewData     = data
                    attachmentPreviewName     = name
                    attachmentPreviewFileType = fileType
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showAttachmentPreview = true
                    }
                },
                onShowOriginal: { vm in
                    guard let msg = vm.latestMessage else { return }
                    originalMessage = msg
                    originalRawSource = nil
                    isLoadingOriginal = true
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showOriginal = true
                    }
                    Task {
                        do {
                            let raw = try await GmailMessageService.shared.getRawMessage(id: msg.id, accountID: vm.accountID)
                            originalRawSource = raw.rawSource
                        } catch {
                            originalRawSource = nil
                        }
                        isLoadingOriginal = false
                    }
                },
                onDownloadMessage: { vm in
                    guard let msg = vm.latestMessage else { return }
                    Task {
                        do {
                            let raw = try await GmailMessageService.shared.getRawMessage(id: msg.id, accountID: vm.accountID)
                            if let source = raw.rawSource {
                                await MainActor.run {
                                    let panel = NSSavePanel()
                                    panel.nameFieldStringValue = "\(msg.subject).eml"
                                    panel.canCreateDirectories = true
                                    guard panel.runModal() == .OK, let url = panel.url else { return }
                                    try? source.data(using: .utf8)?.write(to: url)
                                }
                            }
                        } catch { }
                    }
                },
                onUnsubscribe: { url, oneClick, msgID in
                    await UnsubscribeService.shared.unsubscribe(url: url, oneClick: oneClick, messageID: msgID)
                },
                onPrint: { msg, email in
                    EmailPrintService.shared.printEmail(message: msg, email: email)
                },
                checkUnsubscribed: { msgID in
                    UnsubscribeService.shared.isUnsubscribed(messageID: msgID)
                },
                extractBodyUnsubscribeURL: { html in
                    UnsubscribeService.extractBodyUnsubscribeURL(from: html)
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
        case .labels:
            if let label = selectedLabel {
                await mailboxViewModel.loadFolder(labelIDs: [label.id])
            }
        case .drafts:
            break  // local only
        case .subscriptions:
            break  // populated by SubscriptionsStore.shared, no Gmail query needed
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
        let vm = mailboxViewModel
        let removed = vm.removeOptimistically(msgID)
        selectedEmail = vm.emails.first
        UndoActionManager.shared.schedule(
            label: "Archived",
            onConfirm: { Task { await vm.archive(msgID) } },
            onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
        )
    }

    private func deleteEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        let vm = mailboxViewModel
        let removed = vm.removeOptimistically(msgID)
        selectedEmail = vm.emails.first
        UndoActionManager.shared.schedule(
            label: "Moved to Trash",
            onConfirm: { Task { await vm.trash(msgID) } },
            onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
        )
    }

    private func toggleStarEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        Task { await mailboxViewModel.toggleStar(msgID, isStarred: email.isStarred) }
    }

    private func markUnreadEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        Task { await mailboxViewModel.markAsUnread(msgID) }
    }

    private func emptyTrash() {
        let accountID = selectedAccountID ?? authViewModel.primaryAccount?.id ?? ""
        guard !accountID.isEmpty else { return }
        Task {
            do {
                let label = try await GmailLabelService.shared.getLabel(id: "TRASH", accountID: accountID)
                trashTotalCount = label.messagesTotal ?? 0
            } catch {
                trashTotalCount = mailboxViewModel.emails.count
            }
            guard trashTotalCount > 0 else { return }
            showEmptyTrashConfirm = true
        }
    }

    private func moveToInboxEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        let vm = mailboxViewModel
        let removed = vm.removeOptimistically(msgID)
        selectedEmail = vm.emails.first
        if selectedFolder == .trash {
            UndoActionManager.shared.schedule(
                label: "Moved to Inbox",
                onConfirm: { Task { await vm.untrash(msgID) } },
                onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
            )
        } else {
            UndoActionManager.shared.schedule(
                label: "Moved to Inbox",
                onConfirm: { Task { await vm.moveToInbox(msgID) } },
                onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
            )
        }
    }

    private func deletePermanentlyEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        let vm = mailboxViewModel
        let removed = vm.removeOptimistically(msgID)
        selectedEmail = vm.emails.first
        UndoActionManager.shared.schedule(
            label: "Deleted permanently",
            onConfirm: { Task { await vm.deletePermanently(msgID) } },
            onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
        )
    }

    private func markNotSpamEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        let vm = mailboxViewModel
        let removed = vm.removeOptimistically(msgID)
        selectedEmail = vm.emails.first
        UndoActionManager.shared.schedule(
            label: "Moved to Inbox",
            onConfirm: { Task { await vm.unspam(msgID) } },
            onUndo:    { if let msg = removed { vm.restoreOptimistically(msg) } }
        )
    }

    private func markSpamEmail(_ email: Email) {
        guard let msgID = email.gmailMessageID else { return }
        Task {
            await mailboxViewModel.spam(msgID)
            selectedEmail = mailboxViewModel.emails.first
        }
    }

    private func unsubscribeEmail(_ email: Email) {
        guard let url = email.unsubscribeURL else { return }
        SubscriptionsStore.shared.removeEntry(for: email)
        Task { await UnsubscribeService.shared.unsubscribe(url: url, oneClick: false) }
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
        selectedEmail = nil
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
