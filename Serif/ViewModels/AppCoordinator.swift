import SwiftUI
import Combine

@MainActor
class AppCoordinator: ObservableObject {

    // MARK: - Child ViewModels

    let mailStore: MailStore
    let authViewModel: AuthViewModel
    let mailboxViewModel: MailboxViewModel
    let actionCoordinator: EmailActionCoordinator
    let panelCoordinator = PanelCoordinator()
    let attachmentStore: AttachmentStore
    let subscriptionsStore = SubscriptionsStore.shared

    private var cancellables: Set<AnyCancellable> = []
    private var pendingDraftSelection: Email?
    private let backgroundSyncService = HistorySyncService(api: GmailMessageService.shared)

    // MARK: - Selection State

    @Published var selectedAccountID: String?
    @Published var selectedFolder: Folder = .inbox
    @Published var selectedInboxCategory: InboxCategory? = .all
    @Published var selectedLabel: GmailLabel?
    @Published var selectedEmail: Email?
    @Published var selectedEmailIDs: Set<String> = []

    // MARK: - UI State

    @Published var sidebarExpanded = false
    @Published var searchResetTrigger = 0
    @Published var searchFocusTrigger = false
    @Published var composeMode: ComposeMode = .new
    @Published var signatureForNew: String = ""
    @Published var signatureForReply: String = ""
    @Published var lastRefreshedAt: Date?
    @Published var showEmptyTrashConfirm = false
    @Published var trashTotalCount = 0
    @Published var showEmptySpamConfirm = false
    @Published var spamTotalCount = 0
    @Published var attachmentIndexer: AttachmentIndexer?

    // MARK: - AppStorage

    @Published var undoDuration: Int = UserDefaults.standard.integer(forKey: "undoDuration").nonZeroOr(5) {
        didSet { UserDefaults.standard.set(undoDuration, forKey: "undoDuration") }
    }
    @Published var refreshInterval: Int = UserDefaults.standard.integer(forKey: "refreshInterval").nonZeroOr(120) {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }

    // MARK: - Init

    init() {
        let store = MailStore()
        let vm = MailboxViewModel(accountID: "")
        self.mailStore = store
        self.mailboxViewModel = vm
        self.authViewModel = AuthViewModel()
        self.actionCoordinator = EmailActionCoordinator(mailboxViewModel: vm, mailStore: store)
        self.attachmentStore = AttachmentStore(database: .shared)

        // Forward child objectWillChange so SwiftUI re-renders when nested models update
        vm.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        panelCoordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        NotificationService.shared.onNotificationTapped = { [weak self] messageID, accountID in
            guard let self else { return }
            if self.accountID != accountID {
                self.selectedAccountID = accountID
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            self.navigateToMessage(gmailMessageID: messageID)
        }

        IMAPIdleService.shared.onNewMail = { [weak self] accountID in
            guard let self else { return }
            if accountID == self.accountID && self.selectedFolder == .inbox {
                // User is viewing this account's inbox — full UI refresh + badge
                Task {
                    await self.mailboxViewModel.refreshCurrentFolder(labelIDs: ["INBOX"])
                    await self.mailboxViewModel.loadCategoryUnreadCounts()
                    let unread = self.mailboxViewModel.categoryUnreadCounts[.all] ?? 0
                    NotificationService.shared.updateBadge(unreadCount: unread)
                }
            } else {
                // Not viewing this account's inbox — lightweight history sync for notifications
                let isActiveAccount = accountID == self.accountID
                Task {
                    let result = await self.backgroundSyncService.syncViaHistory(
                        accountID: accountID, labelId: "INBOX", existingMessageIDs: []
                    )
                    if result.succeeded && !result.newMessages.isEmpty {
                        NotificationService.shared.notifyNewEmails(result.newMessages, accountEmail: accountID)
                    }
                    if let historyId = result.latestHistoryId {
                        self.backgroundSyncService.updateStoredHistoryId(historyId, accountID: accountID)
                    }
                    if isActiveAccount {
                        await self.mailboxViewModel.loadCategoryUnreadCounts()
                        let unread = self.mailboxViewModel.categoryUnreadCounts[.all] ?? 0
                        NotificationService.shared.updateBadge(unreadCount: unread)
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    var accountID: String {
        selectedAccountID ?? authViewModel.primaryAccount?.id ?? ""
    }

    var displayedEmails: [Email] {
        if selectedFolder == .drafts { return mailStore.emails(for: .drafts) }
        if selectedFolder == .subscriptions { return subscriptionsStore.entries }
        return mailboxViewModel.emails
    }

    var listIsLoading: Bool {
        selectedFolder == .subscriptions ? subscriptionsStore.isAnalyzing
        : selectedFolder == .drafts ? mailStore.isLoadingGmailDrafts
        : mailboxViewModel.isLoading
    }

    var fromAddress: String {
        authViewModel.primaryAccount?.email ?? ""
    }

    // MARK: - Actions

    func selectNext(_ email: Email?) {
        selectedEmail = email
    }

    func clearSelection() {
        selectedEmail = nil
        selectedEmailIDs = []
    }

    func deselectAll() {
        selectedEmailIDs = []
    }

    func emptyTrashRequested(count: Int) {
        trashTotalCount = count
        showEmptyTrashConfirm = true
    }

    func emptySpamRequested(count: Int) {
        spamTotalCount = count
        showEmptySpamConfirm = true
    }

    func renameLabel(_ label: GmailLabel, to newName: String) async {
        await mailboxViewModel.renameLabel(label, to: newName)
        if selectedLabel?.id == label.id {
            selectedLabel = mailboxViewModel.labels.first { $0.id == label.id }
        }
    }

    func deleteLabel(_ label: GmailLabel) async {
        await mailboxViewModel.deleteLabel(label)
        if selectedLabel?.id == label.id {
            selectedLabel = nil
            if selectedFolder == .labels {
                selectedLabel = mailboxViewModel.labels.filter { !$0.isSystemLabel }.first
            }
        }
    }

    func selectAllEmails() {
        selectedEmailIDs = Set(displayedEmails.map { $0.id.uuidString })
        selectedEmail = nil
    }

    func navigateToMessage(gmailMessageID: String) {
        Task {
            guard let msg = try? await GmailMessageService.shared.getMessage(
                id: gmailMessageID, accountID: accountID, format: "full"
            ) else { return }
            let email = mailboxViewModel.makeEmail(from: msg)
            panelCoordinator.showEmail(email, accountID: accountID)
        }
    }

    func composeNewEmail() {
        composeMode = .new
        let draft = mailStore.createDraft()
        if selectedFolder == .drafts {
            selectedEmail = draft
        } else {
            pendingDraftSelection = draft
            selectedFolder = .drafts
        }
    }

    func startCompose(mode: ComposeMode) {
        composeMode = mode
        let draft = mailStore.createDraft()
        if selectedFolder == .drafts {
            selectedEmail = draft
        } else {
            pendingDraftSelection = draft
            selectedFolder = .drafts
        }
    }

    func discardDraft(id: UUID) {
        composeMode = .new
        mailStore.deleteDraft(id: id)
        selectedEmail = nil
    }

    // MARK: - Per-Account Signatures

    func loadSignatures(for id: String) {
        signatureForNew = UserDefaults.standard.string(forKey: "signatureForNew.\(id)") ?? ""
        signatureForReply = UserDefaults.standard.string(forKey: "signatureForReply.\(id)") ?? ""
    }

    func saveSignatures(for id: String) {
        UserDefaults.standard.set(signatureForNew, forKey: "signatureForNew.\(id)")
        UserDefaults.standard.set(signatureForReply, forKey: "signatureForReply.\(id)")
    }

    // MARK: - Folder Loading

    func loadCurrentFolder() async {
        guard !mailboxViewModel.accountID.isEmpty else { return }
        switch selectedFolder {
        case .inbox:
            if let category = selectedInboxCategory {
                if category == .all {
                    await mailboxViewModel.refreshCurrentFolder(labelIDs: ["INBOX"])
                } else {
                    await mailboxViewModel.refreshCurrentFolder(labelIDs: category.gmailLabelIDs)
                }
            } else {
                await mailboxViewModel.refreshCurrentFolder(labelIDs: ["INBOX"])
            }
        case .labels:
            if let label = selectedLabel {
                await mailboxViewModel.refreshCurrentFolder(labelIDs: [label.id])
            }
        case .drafts:
            await mailStore.syncGmailDrafts(accountID: accountID)
        case .subscriptions:
            break
        case .attachments:
            await mailboxViewModel.loadFolder(labelIDs: [], query: "has:attachment")
        default:
            if let labelID = selectedFolder.gmailLabelID {
                await mailboxViewModel.refreshCurrentFolder(labelIDs: [labelID])
            } else if let query = selectedFolder.gmailQuery {
                await mailboxViewModel.loadFolder(labelIDs: [], query: query)
            }
        }
    }

    // MARK: - Lifecycle Handlers

    func handleAppear() {
        if let account = authViewModel.primaryAccount {
            selectedAccountID = account.id
            mailboxViewModel.accountID = account.id
            NotificationService.shared.viewingInboxAccountID = account.id
            SubscriptionsStore.shared.accountID = account.id
            attachmentStore.accountID = account.id
            loadSignatures(for: account.id)
            let indexer = AttachmentIndexer(
                database: .shared,
                messageService: .shared,
                accountID: account.id
            )
            attachmentIndexer = indexer
            mailboxViewModel.attachmentIndexer = indexer
            IMAPIdleService.shared.startMonitoring(accounts: authViewModel.accounts)
            Task {
                await indexer.setProgressUpdate { [weak attachmentStore] in
                    attachmentStore?.refresh()
                }
                await loadCurrentFolder()
                await mailboxViewModel.loadLabels()
                await mailboxViewModel.loadSendAs()
                await mailboxViewModel.loadCategoryUnreadCounts()
                let unread = mailboxViewModel.categoryUnreadCounts[.all] ?? 0
                NotificationService.shared.updateBadge(unreadCount: unread)
                await GmailProfileService.shared.loadContactPhotos(accountID: account.id)
                lastRefreshedAt = Date()
                await indexer.resumePending()
                await indexer.scanForAttachments()
            }
        } else {
            selectedEmail = mailStore.emails(for: .inbox).first
        }
    }

    func handleFolderChange(_ folder: Folder) {
        NotificationService.shared.viewingInboxAccountID = (folder == .inbox) ? accountID : nil
        if let pending = pendingDraftSelection {
            pendingDraftSelection = nil
            selectedEmail = pending
        } else {
            selectedEmail = nil
        }
        selectedEmailIDs = []
        searchResetTrigger += 1
        if folder != .labels { selectedLabel = nil }
        if folder == .attachments {
            attachmentStore.refresh()
            if let indexer = attachmentIndexer {
                Task {
                    await indexer.scanForAttachments()
                }
            }
        } else if folder == .drafts {
            Task { await mailStore.syncGmailDrafts(accountID: accountID) }
        } else {
            Task { await loadCurrentFolder() }
        }
    }

    func handleLabelChange() {
        guard selectedFolder == .labels, selectedLabel != nil else { return }
        selectedEmail = nil
        selectedEmailIDs = []
        searchResetTrigger += 1
        Task { await loadCurrentFolder() }
    }

    func handleCategoryChange(_ category: InboxCategory?) {
        NotificationService.shared.viewingInboxAccountID = (selectedFolder == .inbox) ? accountID : nil
        selectedEmail = nil
        selectedEmailIDs = []
        searchResetTrigger += 1
        Task { await loadCurrentFolder() }
    }

    func handleAccountChange(_ newID: String?) {
        guard let id = newID else { return }
        // Skip if handleAppear already set up this account
        guard mailboxViewModel.accountID != id else { return }
        // Save current account's signatures before switching
        let oldID = mailboxViewModel.accountID
        if !oldID.isEmpty { saveSignatures(for: oldID) }
        loadSignatures(for: id)
        NotificationService.shared.viewingInboxAccountID = nil
        IMAPIdleService.shared.startMonitoring(accounts: authViewModel.accounts)
        selectedFolder = .inbox
        selectedInboxCategory = .all
        selectedLabel = nil
        selectedEmail = nil
        selectedEmailIDs = []
        searchResetTrigger += 1
        ThumbnailCache.shared.clearAll()
        SubscriptionsStore.shared.accountID = id
        attachmentStore.accountID = id
        attachmentStore.refresh()
        let indexer = AttachmentIndexer(
            database: .shared,
            messageService: .shared,
            accountID: id
        )
        attachmentIndexer = indexer
        mailboxViewModel.attachmentIndexer = indexer
        Task {
            await indexer.setProgressUpdate { [weak attachmentStore] in
                attachmentStore?.refresh()
            }
            await mailboxViewModel.switchAccount(id)
            await loadCurrentFolder()
            await mailboxViewModel.loadLabels()
            await mailboxViewModel.loadSendAs()
            await mailboxViewModel.loadCategoryUnreadCounts()
            let unread = mailboxViewModel.categoryUnreadCounts[.all] ?? 0
            NotificationService.shared.updateBadge(unreadCount: unread)
            await GmailProfileService.shared.loadContactPhotos(accountID: id)
            await indexer.resumePending()
            await indexer.scanForAttachments()
        }
    }

    func handleAccountsChange(_ accounts: [GmailAccount]) {
        if selectedAccountID == nil, let first = accounts.first { selectedAccountID = first.id }
        IMAPIdleService.shared.startMonitoring(accounts: accounts)
    }

    func handleSelectedEmailChange(_ email: Email?) {
        guard let email else { return }
        guard let msgID = email.gmailMessageID,
              let message = mailboxViewModel.messages.first(where: { $0.id == msgID }),
              message.isUnread else { return }
        Task {
            await mailboxViewModel.markAsRead(message)
            await mailboxViewModel.loadCategoryUnreadCounts()
            let unread = mailboxViewModel.categoryUnreadCounts[.all] ?? 0
            NotificationService.shared.updateBadge(unreadCount: unread)
        }
    }
}
