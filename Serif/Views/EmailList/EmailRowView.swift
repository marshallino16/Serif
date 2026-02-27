import SwiftUI

struct EmailRowView: View {
    let email: Email
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Unread indicator
                Circle()
                    .fill(email.isRead ? Color.clear : theme.unreadIndicator)
                    .frame(width: 6, height: 6)

                // Avatar
                AvatarView(
                    initials: email.sender.initials,
                    color: email.sender.avatarColor,
                    size: 36,
                    avatarURL: email.sender.avatarURL,
                    senderDomain: email.sender.domain
                )

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(email.isDraft && email.recipients.isEmpty ? "Draft" : email.sender.name)
                            .font(.system(size: 13, weight: email.isRead ? .medium : .semibold))
                            .foregroundColor(email.isDraft && email.recipients.isEmpty ? theme.textTertiary : theme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(email.date.formattedRelative)
                            .font(.system(size: 11))
                            .foregroundColor(theme.textTertiary)
                    }

                    Text(email.subject)
                        .font(.system(size: 12, weight: email.isRead ? .regular : .medium))
                        .foregroundColor(email.isRead ? theme.textSecondary : theme.textPrimary)
                        .lineLimit(1)

                    Text(email.preview)
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                        .lineLimit(1)

                    if !email.labels.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(email.labels.prefix(3)) { label in
                                LabelChipView(label: label)
                            }
                            if email.labels.count > 3 {
                                Text("+\(email.labels.count - 3)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(theme.textTertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(theme.hoverBackground))
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                // Indicators
                VStack(spacing: 4) {
                    if email.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(theme.avatarRing)
                    }
                    if email.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10))
                            .foregroundColor(theme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? theme.selectedCardBackground : (isHovered ? theme.hoverBackground : Color.clear))
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

