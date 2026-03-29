import SwiftUI

struct iOSEmailRow: View {
    let email: Email
    var isSelected: Bool = false
    @Environment(\.theme) private var theme
    @State private var avatarImage: PlatformImage?

    private var hasRealAvatar: Bool { avatarImage != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar with unread badge overlay
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if hasRealAvatar {
                        // No colored bubble when we have a real image
                    } else {
                        Circle()
                            .fill(Color(hex: email.sender.avatarColor))
                    }

                    if let img = avatarImage {
                        platformImage(img)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                    } else {
                        Text(email.sender.initials)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 38, height: 38)

                // Unread indicator on top-right of avatar
                if !email.isRead {
                    Circle()
                        .fill(theme.accentPrimary)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(theme.detailBackground, lineWidth: 2)
                        )
                        .offset(x: 2, y: -2)
                }
            }
            .frame(width: 38, height: 38)

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

                    if email.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10))
                            .foregroundColor(theme.textTertiary)
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

                // Labels + thread count
                HStack(spacing: 6) {
                    if !email.labels.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(email.labels) { label in
                                    LabelChipView(label: label)
                                }
                            }
                        }
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

    // MARK: - Avatar Loading

    private func loadAvatar() async {
        if let url = email.sender.avatarURL, let img = await AvatarCache.shared.image(for: url) {
            avatarImage = img
            return
        }
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
