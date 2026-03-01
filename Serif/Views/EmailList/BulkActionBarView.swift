import SwiftUI

struct BulkActionBarView: View {
    let count: Int
    let selectedFolder: Folder
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onMarkUnread: () -> Void
    let onMarkRead: () -> Void
    let onToggleStar: () -> Void
    let onMoveToInbox: () -> Void
    let onDeselectAll: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(theme.accentPrimary)

            Text("\(count) emails selected")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            HStack(spacing: 12) {
                if selectedFolder != .archive {
                    actionButton(icon: "archivebox", label: "Archive", action: onArchive)
                }
                if selectedFolder != .trash {
                    actionButton(icon: "trash", label: "Delete", action: onDelete, destructive: true)
                }
                actionButton(icon: "envelope.badge", label: "Unread", action: onMarkUnread)
                actionButton(icon: "envelope.open", label: "Read", action: onMarkRead)
                actionButton(icon: "star", label: "Star", action: onToggleStar)
                if selectedFolder == .archive || selectedFolder == .trash {
                    actionButton(icon: "tray.and.arrow.down", label: "Inbox", action: onMoveToInbox)
                }
            }

            Button {
                onDeselectAll()
            } label: {
                Text("Deselect All")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(theme.cardBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.detailBackground)
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void, destructive: Bool = false) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(destructive ? theme.destructive : theme.textSecondary)
            .frame(width: 64, height: 56)
            .background(theme.cardBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
