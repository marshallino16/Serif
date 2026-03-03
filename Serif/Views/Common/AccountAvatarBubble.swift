import SwiftUI

struct AccountAvatarBubble: View {
    let account: GmailAccount
    let isSelected: Bool
    var size: CGFloat = 34
    let action: () -> Void
    @Environment(\.theme) private var theme

    private var initial: String {
        String(account.displayName.prefix(1)).uppercased()
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Base circle
                Circle().fill(isSelected ? theme.sidebarTextMuted : theme.hoverBackground)
                if !isSelected && account.profilePictureURL == nil {
                    Circle().strokeBorder(theme.divider, lineWidth: 1)
                }

                if let url = account.profilePictureURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill().clipShape(Circle())
                        } else {
                            Text(initial)
                                .font(.system(size: size * 0.38, weight: .semibold))
                                .foregroundColor(isSelected ? .white : theme.textSecondary)
                        }
                    }
                } else {
                    Text(initial)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundColor(isSelected ? .white : theme.textSecondary)
                }

                // Selection ring (photo case only)
                if isSelected && account.profilePictureURL != nil {
                    Circle().strokeBorder(theme.sidebarTextMuted, lineWidth: 2)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .help(account.email)
    }
}
