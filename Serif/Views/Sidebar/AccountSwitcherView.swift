import SwiftUI

struct AccountSwitcherView: View {
    let accounts: [GmailAccount]
    @Binding var selectedAccountID: String?
    let isExpanded: Bool
    let onSignIn: () async -> Void
    let isSigningIn: Bool
    @Environment(\.theme) private var theme

    private var selectedAccount: GmailAccount? {
        accounts.first { $0.id == selectedAccountID }
            ?? accounts.first
    }

    var body: some View {
        Group {
            if isExpanded {
                HStack(spacing: 6) {
                    ForEach(accounts) { account in
                        AccountAvatarBubble(
                            account: account,
                            isSelected: account.id == selectedAccountID
                                || (selectedAccountID == nil && account.id == accounts.first?.id),
                            size: 28
                        ) {
                            selectedAccountID = account.id
                        }
                    }
                    addAccountButton(size: 28)
                    Spacer()
                }
                .padding(.horizontal, 16)
            } else {
                VStack {
                    if let account = selectedAccount {
                        AccountAvatarBubble(
                            account: account,
                            isSelected: true,
                            size: 34
                        ) {
                            selectedAccountID = account.id
                        }
                    } else {
                        addAccountButton(size: 34)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func addAccountButton(size: CGFloat) -> some View {
        Button {
            Task { await onSignIn() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .foregroundColor(theme.sidebarTextMuted)
                Image(systemName: "plus")
                    .font(.system(size: size * 0.32, weight: .medium))
                    .foregroundColor(theme.sidebarTextMuted)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isSigningIn ? 0.5 : 1)
        .disabled(isSigningIn)
        .help("Add account")
    }
}
