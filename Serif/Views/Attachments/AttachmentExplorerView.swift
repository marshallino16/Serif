import SwiftUI

struct AttachmentExplorerView: View {
    @ObservedObject var store: AttachmentStore
    @ObservedObject var panelCoordinator: PanelCoordinator
    let accountID: String
    @State private var downloadingAttachmentID: String?
    @State private var showExclusionRuleAlert = false
    @State private var exclusionRulePattern = ""
    @State private var showRulesPopover = false
    @State private var newRuleText = ""
    @Environment(\.theme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(theme.divider)
            filterBar
            content
        }
        .background(theme.listBackground)
        .onAppear { store.refresh() }
        .alert("Add exclusion rule", isPresented: $showExclusionRuleAlert) {
            TextField("Pattern (e.g. Outlook-*)", text: $exclusionRulePattern)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                store.addExclusionRule(exclusionRulePattern)
            }
        } message: {
            Text("Attachments matching this pattern will be hidden. Use * as wildcard.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attachments")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(theme.textPrimary)

                Spacer()

                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.textTertiary)
                    Text("\(store.stats.indexed)/\(store.stats.total) indexed")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                }
                .opacity(store.isIndexing ? 1 : 0)
            }

            SearchBarView(text: $store.searchQuery)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" file type chip
                filterChip(label: "All", isSelected: store.filterFileType == nil) {
                    store.filterFileType = nil
                }

                // Each file type
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
                    .frame(height: 16)
                    .padding(.horizontal, 4)

                // Direction filters
                filterChip(label: "Received", isSelected: store.filterDirection == .received) {
                    store.filterDirection = store.filterDirection == .received ? nil : .received
                }
                filterChip(label: "Sent", isSelected: store.filterDirection == .sent) {
                    store.filterDirection = store.filterDirection == .sent ? nil : .sent
                }

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)

                rulesChip
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if store.displayedAttachments.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.displayedAttachments) { result in
                            AttachmentCardView(
                                result: result,
                                isSearchActive: !store.searchQuery.isEmpty,
                                accountID: accountID,
                                onTap: { loadAndPreview(result.attachment) },
                                onAddExclusionRule: { pattern in
                                    exclusionRulePattern = pattern
                                    showExclusionRuleAlert = true
                                }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: store.searchQuery.isEmpty ? "paperclip" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(theme.textTertiary)
            Text(store.searchQuery.isEmpty ? "No attachments" : "No results for \"\(store.searchQuery)\"")
                .font(.system(size: 13))
                .foregroundColor(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load & Preview

    private func loadAndPreview(_ attachment: IndexedAttachment) {
        guard downloadingAttachmentID == nil else { return }
        downloadingAttachmentID = attachment.id
        let fileType = Attachment.FileType(rawValue: attachment.fileType) ?? .document
        panelCoordinator.previewAttachment(data: nil, name: attachment.filename, fileType: fileType)
        Task {
            defer { downloadingAttachmentID = nil }
            do {
                let data = try await GmailMessageService.shared.getAttachment(
                    messageID: attachment.messageId,
                    attachmentID: attachment.attachmentId,
                    accountID: accountID
                )
                panelCoordinator.previewAttachment(data: data, name: attachment.filename, fileType: fileType)
            } catch {
                print("[AttachmentExplorer] Preview failed: \(error)")
            }
        }
    }

    // MARK: - Rules Chip

    private var rulesChip: some View {
        Button { showRulesPopover.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                Text(store.exclusionRules.isEmpty ? "Rules" : "Rules (\(store.exclusionRules.count))")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(theme.cardBackground))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showRulesPopover, arrowEdge: .bottom) {
            rulesPopoverContent
        }
    }

    private var rulesPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exclusion Rules")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            if store.exclusionRules.isEmpty {
                Text("Right-click an attachment to add a rule")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
            } else {
                VStack(spacing: 4) {
                    ForEach(store.exclusionRules, id: \.self) { rule in
                        HStack {
                            Text(rule)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(theme.textPrimary)
                            Spacer()
                            Button {
                                store.removeExclusionRule(rule)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Divider()

            HStack(spacing: 6) {
                TextField("Pattern (e.g. image-*)", text: $newRuleText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(minWidth: 140)
                    .onSubmit {
                        guard !newRuleText.isEmpty else { return }
                        store.addExclusionRule(newRuleText)
                        newRuleText = ""
                    }
                Button {
                    guard !newRuleText.isEmpty else { return }
                    store.addExclusionRule(newRuleText)
                    newRuleText = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.accentPrimary)
                }
                .buttonStyle(.plain)
                .disabled(newRuleText.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    // MARK: - Filter Chip

    private func filterChip(icon: String? = nil, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? theme.textInverse : theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isSelected ? theme.accentPrimary : theme.cardBackground))
        }
        .buttonStyle(.plain)
    }
}
