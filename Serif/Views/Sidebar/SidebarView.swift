import SwiftUI

struct SidebarView: View {
    @Binding var selectedFolder: Folder
    @Binding var selectedInboxCategory: InboxCategory?
    @Binding var selectedLabel: GmailLabel?
    @Binding var selectedAccountID: String?
    @Binding var showSettings: Bool
    @Binding var isExpanded: Bool
    @Binding var showHelp: Bool
    @Binding var showDebug: Bool
    @ObservedObject var authViewModel: AuthViewModel
    var categoryUnreadCounts: [InboxCategory: Int] = [:]
    var userLabels: [GmailLabel] = []
    var onRenameLabel: ((GmailLabel, String) -> Void)?
    var onDeleteLabel: ((GmailLabel) -> Void)?
    @Environment(\.theme) private var theme
    @AppStorage("showDebugMenu") private var showDebugMenu = false

    @State private var inboxExpanded = true
    @State private var labelsExpanded = false
    @State private var labelToRename: GmailLabel?
    @State private var labelToDelete: GmailLabel?
    @State private var renameText = ""

    private var sidebarWidth: CGFloat { isExpanded ? 200 : 60 }

    var body: some View {
        VStack(spacing: 0) {
            // Logo
            if isExpanded {
                HStack {
                    Image("SerifLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 12)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                Spacer()
                    .frame(height: 10)
            } else {
                Spacer().frame(height: 52)
            }

            // Account switcher
            AccountSwitcherView(
                accounts: authViewModel.accounts,
                selectedAccountID: $selectedAccountID,
                isExpanded: isExpanded,
                onSignIn: { await authViewModel.signIn() },
                isSigningIn: authViewModel.isSigningIn
            )
            .padding(.bottom, isExpanded ? 12 : 8)

            // Divider
            if isExpanded {
                Rectangle()
                    .fill(theme.sidebarTextMuted.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // Folder navigation
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Folder.allCases) { folder in
                        if folder == .inbox {
                            inboxSection
                        } else if folder == .labels {
                            labelsSection
                        } else {
                            SidebarItemView(
                                folder: folder,
                                isSelected: selectedFolder == folder,
                                isExpanded: isExpanded
                            ) {
                                selectedFolder = folder
                                selectedInboxCategory = nil
                            }
                        }
                    }
                }
                .padding(.horizontal, isExpanded ? 8 : 0)
            }

            // Bottom actions
            VStack(spacing: 2) {
                #if DEBUG
                if showDebugMenu {
                    sidebarButton(icon: "ladybug.fill", label: "Debug") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showDebug = true }
                    }
                }
                #endif
                sidebarButton(icon: "gearshape.fill", label: "Settings") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showSettings = true }
                }
                sidebarButton(icon: "questionmark.circle", label: "Help") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showHelp = true }
                }
            }
            .padding(.horizontal, isExpanded ? 8 : 0)
            .padding(.bottom, 16)
        }
        .frame(width: sidebarWidth)
        .background(theme.sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
        .alert("Rename Label", isPresented: Binding(
            get: { labelToRename != nil },
            set: { if !$0 { labelToRename = nil } }
        )) {
            TextField("Label name", text: $renameText)
            Button("Cancel", role: .cancel) { labelToRename = nil }
            Button("Save") {
                if let label = labelToRename, !renameText.isEmpty {
                    onRenameLabel?(label, renameText)
                }
                labelToRename = nil
            }
        } message: {
            Text("Enter a new name for this label.")
        }
        .alert("Delete Label", isPresented: Binding(
            get: { labelToDelete != nil },
            set: { if !$0 { labelToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { labelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let label = labelToDelete { onDeleteLabel?(label) }
                labelToDelete = nil
            }
        } message: {
            Text("Are you sure? This will remove the label from all messages.")
        }
    }

    // MARK: - Inbox super-category

    private var inboxSection: some View {
        VStack(spacing: 2) {
            InboxParentRow(
                isSelected: selectedFolder == .inbox,
                isExpanded: isExpanded,
                inboxExpanded: $inboxExpanded,
                theme: theme
            ) {
                selectedFolder = .inbox
                selectedInboxCategory = .all
                withAnimation(.easeInOut(duration: 0.2)) { inboxExpanded.toggle() }
            }

            if isExpanded && inboxExpanded {
                ForEach(InboxCategory.allCases) { category in
                    InboxCategoryRow(
                        category: category,
                        isSelected: selectedFolder == .inbox && selectedInboxCategory == category,
                        unreadCount: categoryUnreadCounts[category] ?? 0,
                        theme: theme
                    ) {
                        selectedFolder = .inbox
                        selectedInboxCategory = category
                    }
                }
            }
        }
    }

    // MARK: - Labels section

    private var labelsSection: some View {
        VStack(spacing: 2) {
            LabelsParentRow(
                isSelected: selectedFolder == .labels,
                isExpanded: isExpanded,
                labelsExpanded: $labelsExpanded,
                theme: theme
            ) {
                selectedFolder = .labels
                if let first = userLabels.first, selectedLabel == nil {
                    selectedLabel = first
                }
                withAnimation(.easeInOut(duration: 0.2)) { labelsExpanded.toggle() }
            }

            if isExpanded && labelsExpanded {
                ForEach(userLabels) { label in
                    LabelSidebarRow(
                        label: label,
                        isSelected: selectedFolder == .labels && selectedLabel?.id == label.id,
                        theme: theme,
                        onRename: { labelToRename = $0; renameText = $0.name },
                        onDelete: { labelToDelete = $0 }
                    ) {
                        selectedFolder = .labels
                        selectedLabel = label
                    }
                }
            }
        }
    }

    // MARK: - Generic bottom button

    private func sidebarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isExpanded {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(theme.sidebarTextMuted)
                        .frame(width: 20)
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundColor(theme.sidebarTextMuted)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(Rectangle())
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(theme.sidebarTextMuted)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}
