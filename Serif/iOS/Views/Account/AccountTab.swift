import SwiftUI

struct AccountTab: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.theme) private var theme
    @State private var showSignOutConfirm = false
    @State private var accountToSignOut: GmailAccount?
    @State private var isRefreshingContacts = false
    @State private var accountAvatars: [String: PlatformImage] = [:]

    private var accountID: String { coordinator.accountID }

    var body: some View {
        NavigationStack {
            settingsContent
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
        }
        .alert("Sign Out", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) { accountToSignOut = nil }
            Button("Sign Out", role: .destructive) {
                if let account = accountToSignOut {
                    coordinator.authViewModel.signOut(account)
                }
                accountToSignOut = nil
            }
        } message: {
            Text("Are you sure you want to sign out of \(accountToSignOut?.email ?? "")?")
        }
    }

    // MARK: - Content

    private var settingsContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                accountsSection
                signaturesSection
                contactsSection
                behaviorSection
                notificationsSection
                composeSection
                aiSection
                storageSection
                appearanceSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(theme.detailBackground)
        .task { await loadAccountAvatars() }
    }

    // MARK: - Helpers

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    private var settingsDivider: some View {
        Divider().padding(.leading, 16)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.bottom, 4)
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Accounts")

            settingsCard {
                let accounts = coordinator.authViewModel.accounts
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { settingsDivider }

                    settingsRow {
                        Button {
                            coordinator.selectedAccountID = account.id
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: account.accentColor ?? "#888888"))
                                        .frame(width: 36, height: 36)
                                    if let img = accountAvatars[account.id] {
                                        platformImage(img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 36, height: 36)
                                            .clipShape(Circle())
                                    } else {
                                        Text(String(account.displayName.prefix(1)).uppercased())
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: 36, height: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(theme.textPrimary)
                                    Text(account.email)
                                        .font(.system(size: 13))
                                        .foregroundColor(theme.textSecondary)
                                }

                                Spacer()

                                if coordinator.selectedAccountID == account.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(theme.accentPrimary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                accountToSignOut = account
                                showSignOutConfirm = true
                            } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    }
                }

                settingsDivider

                settingsRow {
                    Button {
                        Task {
                            let accountsBefore = Set(coordinator.authViewModel.accounts.map(\.id))
                            await coordinator.authViewModel.signIn()
                            coordinator.authViewModel.reloadAccounts()
                            await loadAccountAvatars()

                            // Register the newly added account for push notifications
                            let accountsAfter = coordinator.authViewModel.accounts
                            if let newAccount = accountsAfter.first(where: { !accountsBefore.contains($0.id) }),
                               let token = try? TokenStore.shared.retrieve(for: newAccount.id),
                               let refreshToken = token.refreshToken {
                                await PushNotificationService.shared.requestPermissionAndRegister(
                                    email: newAccount.email,
                                    refreshToken: refreshToken,
                                    accountID: newAccount.id
                                )
                            }
                        }
                    } label: {
                        HStack {
                            Label("Add Account", systemImage: "plus.circle")
                                .foregroundColor(theme.accentPrimary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Signatures

    private var signaturesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Signatures")

            let aliases = coordinator.mailboxViewModel.sendAsAliases

            settingsCard {
                if aliases.isEmpty {
                    settingsRow {
                        Text("No aliases available")
                            .foregroundColor(theme.textTertiary)
                    }
                } else {
                    // Alias list with NavigationLink
                    ForEach(Array(aliases.enumerated()), id: \.element.sendAsEmail) { index, alias in
                        if index > 0 { settingsDivider }

                        settingsRow {
                            NavigationLink {
                                iOSSignatureEditorView(alias: alias, accountID: accountID)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(alias.displayName ?? alias.sendAsEmail)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(theme.textPrimary)
                                            if alias.isPrimary == true {
                                                Text("Primary")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(theme.accentPrimary.opacity(0.15))
                                                    .foregroundColor(theme.accentPrimary)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        if let sig = alias.signature, !sig.isEmpty {
                                            Text(sig.strippingHTML.prefix(60))
                                                .font(.system(size: 12))
                                                .foregroundColor(theme.textTertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(theme.textTertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingsDivider

                    // New email signature picker
                    settingsRow {
                        HStack {
                            Text("New email signature")
                                .font(.system(size: 15))
                                .foregroundColor(theme.textPrimary)
                            Spacer()
                            Menu {
                                Picker("New email signature", selection: $coordinator.signatureForNew) {
                                    Text("None").tag("")
                                    ForEach(aliases, id: \.sendAsEmail) { alias in
                                        Text(alias.displayName ?? alias.sendAsEmail).tag(alias.sendAsEmail)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(signatureLabel(for: coordinator.signatureForNew, aliases: aliases))
                                        .foregroundColor(theme.textSecondary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(theme.textTertiary)
                                }
                            }
                        }
                    }

                    settingsDivider

                    // Reply signature picker
                    settingsRow {
                        HStack {
                            Text("Reply signature")
                                .font(.system(size: 15))
                                .foregroundColor(theme.textPrimary)
                            Spacer()
                            Menu {
                                Picker("Reply signature", selection: $coordinator.signatureForReply) {
                                    Text("None").tag("")
                                    ForEach(aliases, id: \.sendAsEmail) { alias in
                                        Text(alias.displayName ?? alias.sendAsEmail).tag(alias.sendAsEmail)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(signatureLabel(for: coordinator.signatureForReply, aliases: aliases))
                                        .foregroundColor(theme.textSecondary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(theme.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func signatureLabel(for email: String, aliases: [GmailSendAs]) -> String {
        if email.isEmpty { return "None" }
        return aliases.first(where: { $0.sendAsEmail == email })?.displayName ?? email
    }

    // MARK: - Contacts

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Contacts")

            settingsCard {
                settingsRow {
                    HStack {
                        Text("Cached contacts")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Text("\(ContactStore.shared.contacts(for: accountID).count)")
                            .foregroundColor(theme.textTertiary)
                    }
                }

                settingsDivider

                settingsRow {
                    Button {
                        Task {
                            isRefreshingContacts = true
                            await GmailProfileService.shared.refreshContacts(accountID: accountID)
                            isRefreshingContacts = false
                        }
                    } label: {
                        HStack {
                            Text("Refresh Contacts")
                                .font(.system(size: 15))
                                .foregroundColor(theme.accentPrimary)
                            Spacer()
                            if isRefreshingContacts {
                                ProgressView()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingContacts)
                }
            }
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Behavior")

            settingsCard {
                // Undo duration picker
                settingsRow {
                    HStack {
                        Text("Undo duration")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Menu {
                            Picker("Undo duration", selection: $coordinator.undoDuration) {
                                Text("5 seconds").tag(5)
                                Text("10 seconds").tag(10)
                                Text("20 seconds").tag(20)
                                Text("30 seconds").tag(30)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(undoDurationLabel)
                                    .foregroundColor(theme.textSecondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(theme.textTertiary)
                            }
                        }
                    }
                }

                settingsDivider

                // Refresh interval picker
                settingsRow {
                    HStack {
                        Text("Refresh interval")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Menu {
                            Picker("Refresh interval", selection: $coordinator.refreshInterval) {
                                Text("2 minutes").tag(120)
                                Text("5 minutes").tag(300)
                                Text("10 minutes").tag(600)
                                Text("1 hour").tag(3600)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(refreshIntervalLabel)
                                    .foregroundColor(theme.textSecondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(theme.textTertiary)
                            }
                        }
                    }
                }

                if let lastRefresh = coordinator.lastRefreshedAt {
                    settingsDivider

                    settingsRow {
                        HStack {
                            Text("Last refresh")
                                .font(.system(size: 15))
                                .foregroundColor(theme.textPrimary)
                            Spacer()
                            Text(lastRefresh, style: .relative)
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private var undoDurationLabel: String {
        switch coordinator.undoDuration {
        case 5: return "5 seconds"
        case 10: return "10 seconds"
        case 20: return "20 seconds"
        case 30: return "30 seconds"
        default: return "\(coordinator.undoDuration)s"
        }
    }

    private var refreshIntervalLabel: String {
        switch coordinator.refreshInterval {
        case 120: return "2 minutes"
        case 300: return "5 minutes"
        case 600: return "10 minutes"
        case 3600: return "1 hour"
        default: return "\(coordinator.refreshInterval)s"
        }
    }

    // MARK: - Notifications

    @ObservedObject private var pushService = PushNotificationService.shared

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Notifications")

            settingsCard {
                if !pushService.notificationsEnabled {
                    settingsRow {
                        HStack {
                            Image(systemName: "bell.slash")
                                .foregroundColor(theme.textTertiary)
                            Text("Notifications disabled")
                                .font(.system(size: 15))
                                .foregroundColor(theme.textSecondary)
                            Spacer()
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.accentPrimary)
                        }
                    }
                } else {
                    ForEach(PushNotificationService.allCategories, id: \.id) { category in
                        settingsRow {
                            HStack {
                                Text(category.name)
                                    .font(.system(size: 15))
                                    .foregroundColor(theme.textPrimary)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { pushService.notifyCategories.contains(category.id) },
                                    set: { _ in Task { await pushService.toggleCategory(category.id) } }
                                ))
                                .tint(.green)
                            }
                        }
                    }
                }
            }

        }
    }

    // MARK: - Compose

    @AppStorage("quoteStyle") private var quoteStyle = "gmail"

    private var composeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Compose")

            settingsCard {
                settingsRow {
                    HStack {
                        Text("Reply quote style")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Menu {
                            Picker("", selection: $quoteStyle) {
                                Text("Gmail style").tag("gmail")
                                Text("Blockquote").tag("blockquote")
                                Text("No quote").tag("noQuote")
                            }
                        } label: {
                            Text(quoteStyleLabel)
                                .font(.system(size: 15))
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private var quoteStyleLabel: String {
        switch quoteStyle {
        case "gmail": return "Gmail style"
        case "blockquote": return "Blockquote"
        case "noQuote": return "No quote"
        default: return "Gmail style"
        }
    }

    // MARK: - Apple Intelligence

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Apple Intelligence")

            settingsCard {
                settingsRow {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: aiLabelSuggestionsBinding) {
                            Text("Label Suggestions")
                                .font(.system(size: 15))
                                .foregroundColor(theme.textPrimary)
                        }
                        .tint(theme.isLight ? theme.accentPrimary : .green)

                        Text("Suggest labels for emails using on-device AI")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textTertiary)
                    }
                }
            }
        }
    }

    private var aiLabelSuggestionsBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: "aiLabelSuggestions") as? Bool ?? true },
            set: { UserDefaults.standard.set($0, forKey: "aiLabelSuggestions") }
        )
    }

    // MARK: - Storage

    @AppStorage("attachmentScanMonths") private var attachmentScanMonths: Int = 6
    @State private var showClearIndexConfirm = false
    @State private var isOptimizingDB = false

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Storage")

            settingsCard {
                // Scan depth picker
                settingsRow {
                    HStack {
                        Text("Scan depth")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Menu {
                            Picker("Scan depth", selection: $attachmentScanMonths) {
                                Text("6 months").tag(6)
                                Text("1 year").tag(12)
                                Text("2 years").tag(24)
                                Text("All time").tag(0)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(scanDepthLabel)
                                    .foregroundColor(theme.textSecondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(theme.textTertiary)
                            }
                        }
                    }
                }

                settingsDivider

                // Attachment count
                settingsRow {
                    HStack {
                        Text("Attachments indexed")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Text("\(coordinator.attachmentStore.stats.indexed)")
                            .foregroundColor(theme.textTertiary)
                    }
                }

                settingsDivider

                // Database size on disk
                settingsRow {
                    HStack {
                        Text("Database size")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Text(formattedDatabaseSize)
                            .foregroundColor(theme.textTertiary)
                    }
                }

                settingsDivider

                // Optimize database
                settingsRow {
                    Button {
                        isOptimizingDB = true
                        DispatchQueue.global(qos: .utility).async {
                            AttachmentDatabase.shared.truncateExtractedText()
                            DispatchQueue.main.async {
                                isOptimizingDB = false
                            }
                        }
                    } label: {
                        HStack {
                            Text("Optimize Database")
                                .font(.system(size: 15))
                                .foregroundColor(theme.accentPrimary)
                            Spacer()
                            if isOptimizingDB {
                                ProgressView()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isOptimizingDB)
                }

                settingsDivider

                // Clear index
                settingsRow {
                    Button {
                        showClearIndexConfirm = true
                    } label: {
                        HStack {
                            Text("Clear Index")
                                .font(.system(size: 15))
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .alert("Clear Index", isPresented: $showClearIndexConfirm) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear", role: .destructive) {
                            ThumbnailCache.shared.clearAll()
                            coordinator.attachmentStore.allAttachments.removeAll()
                            coordinator.attachmentStore.searchResults.removeAll()
                        }
                    } message: {
                        Text("This will remove all cached attachment data. Attachments will need to be re-indexed.")
                    }
                }
            }
        }
    }

    private var scanDepthLabel: String {
        switch attachmentScanMonths {
        case 6: return "6 months"
        case 12: return "1 year"
        case 24: return "2 years"
        case 0: return "All time"
        default: return "\(attachmentScanMonths) months"
        }
    }

    private var formattedDatabaseSize: String {
        let totalBytes = AttachmentDatabase.shared.databaseSizeBytes()
        guard totalBytes > 0 else { return "0 B" }
        if totalBytes < 1024 { return "\(totalBytes) B" }
        if totalBytes < 1024 * 1024 { return "\(totalBytes / 1024) KB" }
        if totalBytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(totalBytes) / (1024 * 1024))
        }
        return String(format: "%.2f GB", Double(totalBytes) / (1024 * 1024 * 1024))
    }

    private var formattedOriginalFilesSize: String {
        // This is the total size of the original files on Gmail servers (NOT stored locally)
        let totalBytes = coordinator.attachmentStore.allAttachments.reduce(0) { $0 + $1.size }
        guard totalBytes > 0 else { return "0 B" }
        if totalBytes < 1024 { return "\(totalBytes) B" }
        if totalBytes < 1024 * 1024 { return "\(totalBytes / 1024) KB" }
        if totalBytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(totalBytes) / (1024 * 1024))
        }
        return String(format: "%.2f GB", Double(totalBytes) / (1024 * 1024 * 1024))
    }

    private func platformImage(_ img: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: img)
        #else
        Image(uiImage: img)
        #endif
    }

    // MARK: - Avatar Loading

    private func loadAccountAvatars() async {
        for account in coordinator.authViewModel.accounts {
            guard let url = account.profilePictureURL else { continue }
            if let img = await AvatarCache.shared.image(for: url.absoluteString) {
                accountAvatars[account.id] = img
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Appearance")

            settingsCard {
                settingsRow {
                    NavigationLink {
                        iOSThemePickerView()
                    } label: {
                        HStack {
                            Label {
                                Text("Theme")
                                    .font(.system(size: 15))
                                    .foregroundColor(theme.textPrimary)
                            } icon: {
                                Image(systemName: "paintpalette")
                                    .foregroundColor(theme.accentPrimary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(theme.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("About")

            settingsCard {
                settingsRow {
                    HStack {
                        Text("Version")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                            .foregroundColor(theme.textTertiary)
                    }
                }
            }
        }
    }
}

// MARK: - Signature Editor

struct iOSSignatureEditorView: View {
    let alias: GmailSendAs
    let accountID: String
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var signatureHTML: String = ""
    @State private var isSaving = false
    @StateObject private var editorState = WebRichTextEditorState()

    var body: some View {
        VStack(spacing: 0) {
            iOSFormattingToolbar(state: editorState)

            Divider()

            iOSWebRichTextEditor(
                state: editorState,
                htmlContent: $signatureHTML,
                placeholder: "Enter your signature…",
                autoFocus: false
            )
        }
        .background(theme.detailBackground)
        .navigationTitle(alias.displayName ?? alias.sendAsEmail)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await saveSignature() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save") }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            signatureHTML = alias.signature ?? ""
        }
    }

    private func saveSignature() async {
        isSaving = true
        let html = await editorState.getHTMLAsync()
        _ = try? await GmailProfileService.shared.updateSignature(
            sendAsEmail: alias.sendAsEmail,
            signature: html,
            accountID: accountID
        )
        isSaving = false
        dismiss()
    }
}
