import SwiftUI

struct AttachmentsListView: View {
    @ObservedObject var mailboxViewModel: MailboxViewModel
    @Binding var selectedEmail: Email?
    @State private var searchText = ""
    @State private var selectedDirection: AttachmentItem.Direction? = nil
    @State private var selectedFileType: Attachment.FileType? = nil
    @Environment(\.theme) private var theme

    private var allItems: [AttachmentItem] {
        mailboxViewModel.allAttachmentItems()
    }

    private var filteredItems: [AttachmentItem] {
        var items = allItems

        if let direction = selectedDirection {
            items = items.filter { $0.direction == direction }
        }

        if let fileType = selectedFileType {
            items = items.filter { $0.attachment.fileType == fileType }
        }

        if !searchText.isEmpty {
            items = items.filter {
                $0.attachment.name.localizedCaseInsensitiveContains(searchText) ||
                $0.senderName.localizedCaseInsensitiveContains(searchText) ||
                $0.emailSubject.localizedCaseInsensitiveContains(searchText) ||
                $0.attachment.fileType.label.localizedCaseInsensitiveContains(searchText)
            }
        }

        return items
    }

    private var availableFileTypes: [Attachment.FileType] {
        let types = Set(allItems.map(\.attachment.fileType))
        return Attachment.FileType.allCases.filter { types.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Attachments")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(theme.textPrimary)

                    Spacer()

                    Text("\(filteredItems.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.cardBackground)
                        .cornerRadius(4)
                }

                SearchBarView(text: $searchText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterPill(label: "All", isSelected: selectedDirection == nil) {
                            selectedDirection = nil
                        }
                        ForEach(AttachmentItem.Direction.allCases, id: \.self) { direction in
                            filterPill(
                                label: direction.rawValue,
                                isSelected: selectedDirection == direction
                            ) {
                                selectedDirection = selectedDirection == direction ? nil : direction
                            }
                        }

                        Divider()
                            .frame(height: 16)
                            .padding(.horizontal, 4)

                        ForEach(availableFileTypes, id: \.self) { fileType in
                            filterPill(
                                icon: fileType.rawValue,
                                label: fileType.label,
                                isSelected: selectedFileType == fileType
                            ) {
                                selectedFileType = selectedFileType == fileType ? nil : fileType
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .background(theme.divider)

            if mailboxViewModel.isLoading && allItems.isEmpty {
                VStack {
                    Spacer()
                    ProgressView().scaleEffect(0.8).tint(theme.textTertiary)
                    Spacer()
                }
            } else if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredItems) { item in
                            AttachmentRowView(item: item) {
                                if let email = mailboxViewModel.emails.first(where: { $0.id == item.emailId }) {
                                    selectedEmail = email
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(theme.listBackground)
    }

    // MARK: - Filter pill

    private func filterPill(icon: String? = nil, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "paperclip")
                .font(.system(size: 28))
                .foregroundColor(theme.textTertiary)
            Text("No attachments found")
                .font(.system(size: 13))
                .foregroundColor(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Attachment Row

struct AttachmentRowView: View {
    let item: AttachmentItem
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.cardBackground)
                    Image(systemName: item.attachment.fileType.rawValue)
                        .font(.system(size: 16))
                        .foregroundColor(theme.accentPrimary)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.attachment.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: item.direction == .received ? "arrow.down.left" : "arrow.up.right")
                                .font(.system(size: 8))
                            Text(item.direction.rawValue)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(item.direction == .received ? theme.accentPrimary : theme.accentSecondary)

                        Text("·")
                            .foregroundColor(theme.textTertiary)

                        Text(item.senderName)
                            .font(.system(size: 11))
                            .foregroundColor(theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if !item.attachment.size.isEmpty {
                        Text(item.attachment.size)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                    }

                    Text(item.date.formattedRelative)
                        .font(.system(size: 10))
                        .foregroundColor(theme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? theme.hoverBackground : Color.clear)
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
