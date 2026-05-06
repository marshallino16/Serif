import SwiftUI

struct iOSLabelManagementSheet: View {
    let email: Email
    @ObservedObject var detailVM: EmailDetailViewModel
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isCreatingLabel = false

    private var allLabels: [GmailLabel] {
        coordinator.mailboxViewModel.labels.filter { !$0.isSystemLabel }
    }

    private var filteredLabels: [GmailLabel] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return allLabels }
        return allLabels.filter { $0.displayName.lowercased().contains(query) }
    }

    private var showCreateOption: Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return false }
        return !allLabels.contains { $0.displayName.caseInsensitiveCompare(query) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                // Current labels section
                if !currentUserLabels.isEmpty {
                    Section("Applied Labels") {
                        ForEach(currentUserLabels) { label in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: label.resolvedBgColor))
                                    .frame(width: 12, height: 12)
                                Text(label.displayName)
                                    .font(.system(size: 15))
                                    .foregroundColor(theme.textPrimary)
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(theme.accentPrimary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                removeLabel(label)
                            }
                        }
                    }
                }

                // Available labels
                Section("All Labels") {
                    ForEach(filteredLabels) { label in
                        let isApplied = currentLabelIDs.contains(label.id)
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: label.resolvedBgColor))
                                .frame(width: 12, height: 12)
                            Text(label.displayName)
                                .font(.system(size: 15))
                                .foregroundColor(theme.textPrimary)
                            Spacer()
                            if isApplied {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(theme.accentPrimary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isApplied {
                                removeLabel(label)
                            } else {
                                addLabel(label)
                            }
                        }
                    }

                    // Create new label option
                    if showCreateOption {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(theme.accentPrimary)
                            Text("Create \"\(searchText.trimmingCharacters(in: .whitespaces))\"")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(theme.accentPrimary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            createNewLabel()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search labels...")
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isCreatingLabel {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Computed

    private var currentLabelIDs: [String] {
        detailVM.latestMessage?.labelIds ?? email.gmailLabelIDs
    }

    private var currentUserLabels: [GmailLabel] {
        let ids = Set(currentLabelIDs)
        return allLabels.filter { ids.contains($0.id) }
    }

    // MARK: - Actions

    private func addLabel(_ label: GmailLabel) {
        guard !currentLabelIDs.contains(label.id) else { return }
        var newIDs = currentLabelIDs
        newIDs.append(label.id)
        detailVM.updateLabelIDs(newIDs)
        if let msgID = email.gmailMessageID {
            Task {
                await coordinator.mailboxViewModel.addLabel(label.id, to: msgID)
            }
        }
    }

    private func removeLabel(_ label: GmailLabel) {
        let newIDs = currentLabelIDs.filter { $0 != label.id }
        detailVM.updateLabelIDs(newIDs)
        if let msgID = email.gmailMessageID {
            Task {
                await coordinator.mailboxViewModel.removeLabel(label.id, from: msgID)
            }
        }
    }

    private func createNewLabel() {
        let name = searchText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let msgID = email.gmailMessageID else { return }
        isCreatingLabel = true
        searchText = ""
        Task {
            let labelID = await coordinator.mailboxViewModel.createAndAddLabel(name: name, to: msgID)
            if let labelID {
                var newIDs = currentLabelIDs
                newIDs.append(labelID)
                detailVM.updateLabelIDs(newIDs)
            }
            isCreatingLabel = false
        }
    }
}
