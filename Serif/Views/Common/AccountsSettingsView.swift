import SwiftUI
import BlossomColorPicker

struct AccountsSettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Binding var selectedAccountID: String?
    @AppStorage("isSignedIn") private var isSignedIn: Bool = true
    @Environment(\.theme) private var theme
    @State private var colorBindings: [String: Color] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connected Accounts")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            if authViewModel.accounts.isEmpty {
                Text("No accounts connected")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(authViewModel.accounts.enumerated()), id: \.element.id) { index, account in
                        accountRow(account, index: index)
                    }
                }
            }

            // Add account button
            Button {
                Task { await authViewModel.signIn() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text(authViewModel.isSigningIn ? "Signing in…" : "Add account")
                        .font(.system(size: 13))
                }
                .foregroundColor(theme.accentPrimary)
            }
            .buttonStyle(.plain)
            .disabled(authViewModel.isSigningIn)
            .opacity(authViewModel.isSigningIn ? 0.6 : 1)
        }
        .cardStyle()
    }

    private func accountRow(_ account: GmailAccount, index: Int) -> some View {
        let isSelected = account.id == selectedAccountID
            || (selectedAccountID == nil && account.id == authViewModel.accounts.first?.id)
        let isFirst = index == 0
        let isLast = index == authViewModel.accounts.count - 1
        let showReorder = authViewModel.accounts.count > 1

        return HStack(spacing: 10) {
            // Reorder arrows
            if showReorder {
                VStack(spacing: 0) {
                    Button {
                        AccountStore.shared.moveUp(id: account.id)
                        authViewModel.reloadAccounts()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(isFirst ? theme.textTertiary.opacity(0.3) : theme.textTertiary)
                            .frame(width: 16, height: 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFirst)

                    Button {
                        AccountStore.shared.moveDown(id: account.id)
                        authViewModel.reloadAccounts()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(isLast ? theme.textTertiary.opacity(0.3) : theme.textTertiary)
                            .frame(width: 16, height: 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                }
            }

            // Avatar — tap to switch
            AccountAvatarBubble(
                account: account,
                isSelected: isSelected,
                size: 34
            ) {
                selectedAccountID = account.id
            }

            // Account info
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                Text(account.email)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Accent color picker
            BlossomColorPicker(selection: Binding(
                get: { colorBindings[account.id] ?? Color(hex: account.accentColor ?? "#FF6B6B") },
                set: { newColor in
                    colorBindings[account.id] = newColor
                    AccountStore.shared.setAccentColor(id: account.id, hex: newColor.hexString)
                    authViewModel.reloadAccounts()
                }
            ))
            .frame(width: 24, height: 24)

            // Default badge or set-as-default button
            if isFirst {
                Text("Default")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.accentPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.accentPrimary.opacity(0.12))
                    .cornerRadius(4)
            } else {
                Button {
                    AccountStore.shared.setAsDefault(id: account.id)
                    authViewModel.reloadAccounts()
                    selectedAccountID = account.id
                } label: {
                    Image(systemName: "star")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                        .padding(4)
                        .background(theme.hoverBackground)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Set as default")
            }

            // Sign out
            Button {
                authViewModel.signOut(account)
                if isSelected {
                    selectedAccountID = authViewModel.accounts.first?.id
                }
                if authViewModel.accounts.isEmpty {
                    isSignedIn = false
                }
            } label: {
                Text("Sign out")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.hoverBackground)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.divider, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? theme.accentPrimary.opacity(0.07) : Color.clear)
        )
    }
}
