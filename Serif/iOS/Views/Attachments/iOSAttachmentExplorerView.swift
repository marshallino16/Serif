import SwiftUI

struct iOSAttachmentExplorerView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var store: AttachmentStore
    @Environment(\.theme) private var theme

    @State private var isGridMode = true
    @State private var previewAttachment: IndexedAttachment?
    @State private var previewData: Data?
    @State private var isLoadingPreview = false
    @State private var previewError: String?
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var displayOffset = 0
    @State private var showExclusionRules = false
    @State private var newExclusionRule = ""

    private let pageSize = 50

    private var accountID: String { coordinator.accountID }

    private let gridColumns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]

    // MARK: - Computed

    private var formattedStorageSize: String {
        let totalBytes = store.allAttachments.reduce(0) { $0 + $1.size }
        guard totalBytes > 0 else { return "0 B" }
        if totalBytes < 1024 { return "\(totalBytes) B" }
        if totalBytes < 1024 * 1024 { return "\(totalBytes / 1024) KB" }
        if totalBytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(totalBytes) / (1024 * 1024))
        }
        return String(format: "%.2f GB", Double(totalBytes) / (1024 * 1024 * 1024))
    }

    private var displayedResults: [AttachmentSearchResult] {
        Array(store.displayedAttachments.prefix(displayOffset + pageSize))
    }

    private var hasMore: Bool {
        displayOffset + pageSize < store.displayedAttachments.count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter chips below the title (matches InboxTab category picker pattern)
                if !store.allAttachments.isEmpty || store.isIndexing {
                    filterBar
                    Divider().foregroundColor(theme.divider)
                }

                if store.allAttachments.isEmpty && !store.isIndexing {
                    emptyState
                } else if store.isIndexing && store.allAttachments.isEmpty {
                    indexingState
                } else {
                    mainContent
                }
            }
            .background(theme.detailBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Attachments")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                        if store.isIndexing {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        // Exclusion rules button
                        Button {
                            showExclusionRules = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }

                        // Grid/List toggle
                        Button {
                            withAnimation { isGridMode.toggle() }
                        } label: {
                            Image(systemName: isGridMode ? "list.bullet" : "square.grid.2x2")
                        }
                    }
                }
            }
            .searchable(text: Binding(
                get: { store.searchQuery },
                set: { store.searchQuery = $0 }
            ), prompt: "Search attachments...")
            .onSubmit(of: .search) {
                store.performSearch(query: store.searchQuery)
            }
        }
        .onAppear {
            store.refresh()
            displayOffset = 0
        }
        .onChange(of: store.filterFileType) { _, _ in
            displayOffset = 0
        }
        .onChange(of: store.filterDirection) { _, _ in
            displayOffset = 0
        }
        .sheet(item: $previewAttachment) { attachment in
            if let data = previewData {
                let fileType = Attachment.FileType(rawValue: attachment.fileType) ?? .document
                iOSAttachmentPreviewView(
                    data: data,
                    fileName: attachment.filename,
                    fileType: fileType,
                    onShare: {
                        shareAttachment(data: data, filename: attachment.filename)
                    }
                )
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if !shareItems.isEmpty {
                ActivityViewController(activityItems: shareItems)
            }
        }
        .sheet(isPresented: $showExclusionRules) {
            exclusionRulesSheet
                .environment(\.theme, theme)
        }
        .sheet(item: $emailToView) { email in
            NavigationStack {
                iOSEmailDetailView(email: email, coordinator: coordinator)
            }
            .environment(\.theme, theme)
        }
        .overlay {
            if isLoadingPreview {
                previewLoadingOverlay
            }
        }
        .overlay {
            if let error = previewError {
                previewErrorToast(error)
            }
        }
    }

    // MARK: - Preview Loading Overlay

    private var previewLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Downloading...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: isLoadingPreview)
    }

    // MARK: - Preview Error Toast

    private func previewErrorToast(_ message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    previewError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray)))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: previewError != nil)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                previewError = nil
            }
        }
    }

    // MARK: - Header Stats

    private var headerStats: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("\(store.allAttachments.count) attachments")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
            }

            Spacer()

            // Storage size
            Text(formattedStorageSize)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // File type filters
                filterChip(label: "All", isSelected: store.filterFileType == nil) {
                    store.filterFileType = nil
                }

                ForEach(Attachment.FileType.allCases, id: \.self) { fileType in
                    filterChip(
                        icon: fileType.rawValue,
                        label: fileType.label,
                        isSelected: store.filterFileType == fileType
                    ) {
                        store.filterFileType = store.filterFileType == fileType ? nil : fileType
                    }
                }

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 2)

                // Direction filters
                filterChip(label: "Received", isSelected: store.filterDirection == .received) {
                    store.filterDirection = store.filterDirection == .received ? nil : .received
                }
                filterChip(label: "Sent", isSelected: store.filterDirection == .sent) {
                    store.filterDirection = store.filterDirection == .sent ? nil : .sent
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Applied Filters

    @ViewBuilder
    private var appliedFilters: some View {
        let hasFilters = store.filterFileType != nil || store.filterDirection != nil
        if hasFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let ft = store.filterFileType {
                        removableChip(label: ft.label) {
                            store.filterFileType = nil
                        }
                    }
                    if let dir = store.filterDirection {
                        removableChip(label: dir == .received ? "Received" : "Sent") {
                            store.filterDirection = nil
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {

            if isGridMode {
                gridContent
            } else {
                listContent
            }
        }
    }

    // MARK: - Grid Content

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(displayedResults) { result in
                    iOSAttachmentCardView(
                        result: result,
                        isSearchActive: !store.searchQuery.isEmpty,
                        accountID: accountID,
                        onTap: { loadAndPreview(result.attachment) },
                        onShare: { downloadAndShare(result.attachment) },
                        onViewMessage: { navigateToEmail(result.attachment.messageId) },
                        onAddExclusionRule: { pattern in
                            store.addExclusionRule(pattern)
                        }
                    )
                }

                // Load more trigger
                if hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { loadMore() }
                }
            }
            .padding(16)
        }
        .refreshable { await refreshAttachments() }
    }

    // MARK: - List Content

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedResults) { result in
                    iOSAttachmentListRow(
                        result: result,
                        accountID: accountID,
                        onTap: { loadAndPreview(result.attachment) },
                        onShare: { downloadAndShare(result.attachment) },
                        onViewMessage: { navigateToEmail(result.attachment.messageId) },
                        onAddExclusionRule: { pattern in
                            store.addExclusionRule(pattern)
                        }
                    )

                    Divider()
                        .padding(.leading, 72)
                }

                // Load more trigger
                if hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { loadMore() }
                }
            }
        }
        .refreshable { await refreshAttachments() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: store.searchQuery.isEmpty ? "paperclip" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(theme.textTertiary)

            Text(store.searchQuery.isEmpty
                 ? "No attachments yet"
                 : "No results for \"\(store.searchQuery)\"")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(theme.textSecondary)

            if store.searchQuery.isEmpty {
                Text("Start a scan to find your email attachments")
                    .font(.system(size: 14))
                    .foregroundColor(theme.textTertiary)
                    .multilineTextAlignment(.center)

                Button {
                    store.refresh()
                } label: {
                    Text("Start Scan")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(theme.accentPrimary))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    // MARK: - Scanning State

    private var indexingState: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Scanning attachments...")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(theme.textSecondary)

            if store.stats.total > 0 {
                ProgressView(value: Double(store.stats.indexed), total: Double(store.stats.total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
                    .tint(theme.accentPrimary)

                Text("\(store.stats.indexed) of \(store.stats.total) scanned")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    // MARK: - Filter Chip

    private func filterChip(icon: String? = nil, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? theme.textInverse : theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(isSelected ? theme.accentPrimary : theme.cardBackground))
        }
        .buttonStyle(.plain)
    }

    private func removableChip(label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
        }
        .foregroundColor(theme.accentPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(theme.accentPrimary.opacity(0.12)))
    }

    // MARK: - Exclusion Rules Sheet

    private var exclusionRulesSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Add rule row
                HStack(spacing: 10) {
                    TextField("Pattern (e.g. *.png, Outlook-*)", text: $newExclusionRule)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            addRule()
                        }

                    Button {
                        addRule()
                    } label: {
                        Text("Add")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(newExclusionRule.isEmpty ? theme.textTertiary : theme.accentPrimary))
                    }
                    .buttonStyle(.plain)
                    .disabled(newExclusionRule.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                if store.exclusionRules.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "eye.slash")
                            .font(.system(size: 32))
                            .foregroundColor(theme.textTertiary)
                        Text("No exclusion rules")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                        Text("Files matching these patterns will be hidden\n(e.g., *.png, Outlook-*)")
                            .font(.system(size: 13))
                            .foregroundColor(theme.textTertiary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                } else {
                    List {
                        Section {
                            ForEach(store.exclusionRules, id: \.self) { rule in
                                HStack {
                                    Image(systemName: "eye.slash")
                                        .font(.system(size: 13))
                                        .foregroundColor(theme.textTertiary)
                                    Text(rule)
                                        .font(.system(size: 15, design: .monospaced))
                                        .foregroundColor(theme.textPrimary)
                                    Spacer()
                                }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    store.removeExclusionRule(store.exclusionRules[index])
                                }
                            }
                        } footer: {
                            Text("Files matching these patterns will be hidden (e.g., *.png, Outlook-*). Swipe to delete a rule.")
                                .font(.system(size: 12))
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(theme.detailBackground)
            .navigationTitle("Exclusion Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showExclusionRules = false
                    }
                }
            }
        }
    }

    private func addRule() {
        let trimmed = newExclusionRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addExclusionRule(trimmed)
        newExclusionRule = ""
    }

    // MARK: - Actions

    private func loadMore() {
        displayOffset += pageSize
    }

    private func refreshAttachments() async {
        store.refresh()
        displayOffset = 0
        // Small delay so pull-to-refresh feels responsive
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func loadAndPreview(_ attachment: IndexedAttachment) {
        guard !isLoadingPreview else { return }
        let fileType = Attachment.FileType(rawValue: attachment.fileType) ?? .document

        guard fileType.isPreviewable else {
            downloadAndShare(attachment)
            return
        }

        isLoadingPreview = true
        previewError = nil
        Task {
            do {
                let data = try await GmailMessageService.shared.getAttachment(
                    messageID: attachment.messageId,
                    attachmentID: attachment.attachmentId,
                    accountID: accountID
                )
                isLoadingPreview = false
                previewData = data
                previewAttachment = attachment
            } catch {
                isLoadingPreview = false
                previewError = "Failed to download \(attachment.filename)"
                print("[iOSAttachmentExplorer] Preview failed: \(error)")
            }
        }
    }

    private func downloadAndShare(_ attachment: IndexedAttachment) {
        guard !isLoadingPreview else { return }
        isLoadingPreview = true
        previewError = nil
        Task {
            do {
                let data = try await GmailMessageService.shared.getAttachment(
                    messageID: attachment.messageId,
                    attachmentID: attachment.attachmentId,
                    accountID: accountID
                )
                isLoadingPreview = false
                shareAttachment(data: data, filename: attachment.filename)
            } catch {
                isLoadingPreview = false
                previewError = "Failed to download \(attachment.filename)"
                print("[iOSAttachmentExplorer] Share download failed: \(error)")
            }
        }
    }

    private func shareAttachment(data: Data, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        shareItems = [tempURL]
        showShareSheet = true
    }

    @State private var emailToView: Email?

    private func navigateToEmail(_ messageId: String) {
        Task {
            do {
                let message = try await GmailMessageService.shared.getMessage(
                    id: messageId, accountID: accountID, format: "full"
                )
                let email = coordinator.mailboxViewModel.makeEmail(from: message)
                await MainActor.run { emailToView = email }
            } catch {
                print("[iOSAttachmentExplorer] Navigate to email failed: \(error)")
            }
        }
    }
}

// MARK: - IndexedAttachment conformances for .sheet(item:)

extension IndexedAttachment: Equatable {
    static func == (lhs: IndexedAttachment, rhs: IndexedAttachment) -> Bool {
        lhs.id == rhs.id
    }
}

extension IndexedAttachment: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Share Sheet

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
