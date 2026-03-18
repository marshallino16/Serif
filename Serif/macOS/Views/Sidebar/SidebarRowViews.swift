import SwiftUI

// MARK: - Inbox Parent Row

struct InboxParentRow: View {
    let isSelected: Bool
    let isExpanded: Bool
    @Binding var inboxExpanded: Bool
    let theme: Theme
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            if isExpanded {
                HStack(spacing: 10) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? theme.sidebarAccent : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                        .frame(width: 20)

                    Text("Inbox")
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? theme.sidebarText : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer()

                    // Chevron to expand/collapse subcategories
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { inboxExpanded.toggle() }
                    } label: {
                        Image(systemName: inboxExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(theme.sidebarTextMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? theme.sidebarSelectedBg : (isHovered ? theme.sidebarHover : Color.clear))
                )
                .contentShape(Rectangle())
            } else {
                // Collapsed: just the icon with dot if needed
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10).fill(theme.sidebarSelectedBg)
                    }
                    Image(systemName: "tray.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isSelected ? theme.sidebarAccent : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isExpanded ? "" : "Inbox")
    }
}

// MARK: - Inbox Category Row

struct InboxCategoryRow: View {
    let category: InboxCategory
    let isSelected: Bool
    let unreadCount: Int
    let theme: Theme
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Indent marker
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)

                Image(systemName: category.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? theme.sidebarAccent : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                    .frame(width: 16)

                Text(category.displayName)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? theme.sidebarText : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))

                Spacer()

                if unreadCount > 0 {
                    BadgeView(count: unreadCount, isSelected: isSelected)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? theme.sidebarSelectedBg : (isHovered ? theme.sidebarHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Labels Parent Row

struct LabelsParentRow: View {
    let isSelected: Bool
    let isExpanded: Bool
    @Binding var labelsExpanded: Bool
    let theme: Theme
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            if isExpanded {
                HStack(spacing: 10) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? theme.sidebarAccent : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                        .frame(width: 20)

                    Text("Labels")
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? theme.sidebarText : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { labelsExpanded.toggle() }
                    } label: {
                        Image(systemName: labelsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(theme.sidebarTextMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? theme.sidebarSelectedBg : (isHovered ? theme.sidebarHover : Color.clear))
                )
                .contentShape(Rectangle())
            } else {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10).fill(theme.sidebarSelectedBg)
                    }
                    Image(systemName: "tag.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isSelected ? theme.sidebarAccent : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isExpanded ? "" : "Labels")
    }
}

// MARK: - Label Sidebar Row

struct LabelSidebarRow: View {
    let label: GmailLabel
    let isSelected: Bool
    let theme: Theme
    var onRename: ((GmailLabel) -> Void)?
    var onDelete: ((GmailLabel) -> Void)?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)

                Circle()
                    .fill(Color(hex: label.resolvedTextColor))
                    .frame(width: 8, height: 8)

                Text(label.displayName)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? theme.sidebarText : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()

                if let unread = label.messagesUnread, unread > 0 {
                    BadgeView(count: unread, isSelected: isSelected)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? theme.sidebarSelectedBg : (isHovered ? theme.sidebarHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Rename...") { onRename?(label) }
            Divider()
            Button("Delete", role: .destructive) { onDelete?(label) }
        }
    }
}

// MARK: - Generic Folder Item

struct SidebarItemView: View {
    let folder: Folder
    let isSelected: Bool
    let isExpanded: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            if isExpanded { expandedContent } else { collapsedContent }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isExpanded ? "" : folder.rawValue)
    }

    private var expandedContent: some View {
        HStack(spacing: 10) {
            Image(systemName: folder.icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? theme.sidebarAccent : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                .frame(width: 20)

            Text(folder.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? theme.sidebarText : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                .fixedSize(horizontal: true, vertical: false)
            Spacer()

            if folder.count > 0 {
                Text("\(folder.count)")
                    .font(.serifSmallMedium)
                    .foregroundColor(isSelected ? theme.sidebarBadgeText : theme.sidebarTextMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(isSelected ? theme.sidebarBadge : theme.sidebarBadge))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? theme.sidebarSelectedBg : (isHovered ? theme.sidebarHover : Color.clear))
        )
        .contentShape(Rectangle())
    }

    private var collapsedContent: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 10).fill(theme.sidebarSelectedBg)
            }
            ZStack(alignment: .topTrailing) {
                Image(systemName: folder.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? theme.sidebarAccent : (isHovered ? theme.sidebarTextHover : theme.sidebarTextMuted))
                if folder.count > 0 {
                    Circle().fill(theme.sidebarAccent).frame(width: 8, height: 8).offset(x: 4, y: -2)
                }
            }
        }
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }
}
