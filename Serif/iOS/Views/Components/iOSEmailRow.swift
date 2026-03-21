import SwiftUI

struct iOSEmailRow: View {
    let email: Email
    var isSelected: Bool = false
    @Environment(\.theme) private var theme
    @State private var avatarImage: PlatformImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread indicator
            Circle()
                .fill(email.isRead ? Color.clear : theme.accentPrimary)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            // Avatar
            ZStack {
                Circle()
                    .fill(Color(hex: email.sender.avatarColor))
                    .frame(width: 36, height: 36)

                if let img = avatarImage {
                    platformImage(img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } else {
                    Text(email.sender.initials)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 36, height: 36)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(email.sender.name.isEmpty ? email.sender.email : email.sender.name)
                        .font(.system(size: 14, weight: email.isRead ? .regular : .semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    if email.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                    }

                    Spacer()

                    Text(email.date.formattedRelative)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                }

                Text(email.subject)
                    .font(.system(size: 13, weight: email.isRead ? .regular : .medium))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                Text(email.preview)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)

                // Labels
                if !email.labels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(email.labels) { label in
                                LabelChipView(label: label)
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    if email.hasAttachments {
                        HStack(spacing: 3) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 10))
                            Text("Attachment")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(theme.textTertiary)
                    }

                    if email.threadMessageCount > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(email.threadMessageCount)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(theme.textTertiary.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundColor(theme.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .task(id: email.sender.email) {
            await loadAvatar()
        }
    }

    // MARK: - Avatar Loading (same pipeline as macOS AvatarView)

    private func loadAvatar() async {
        // 1. Contact photo / Gravatar (already resolved in Contact.avatarURL)
        if let url = email.sender.avatarURL, let img = await AvatarCache.shared.image(for: url) {
            avatarImage = img
            return
        }

        // 2. BIMI logo for organization domains
        if let domain = email.sender.domain {
            if let bimiURL = await BIMIService.shared.logoURL(for: domain),
               let img = await AvatarCache.shared.image(for: bimiURL) {
                avatarImage = img
            }
        }
    }

    private func platformImage(_ img: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: img)
        #else
        Image(uiImage: img)
        #endif
    }
}
