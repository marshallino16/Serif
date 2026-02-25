import SwiftUI

struct AccountsSettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Binding var selectedAccountID: String?
    @AppStorage("isSignedIn") private var isSignedIn: Bool = true
    @Environment(\.theme) private var theme

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
                    ForEach(authViewModel.accounts) { account in
                        accountRow(account)
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
        .padding(20)
        .background(theme.cardBackground)
        .cornerRadius(12)
    }

    private func accountRow(_ account: GmailAccount) -> some View {
        let isSelected = account.id == selectedAccountID
            || (selectedAccountID == nil && account.id == authViewModel.accounts.first?.id)
        let initial = String(account.displayName.prefix(1)).uppercased()

        return HStack(spacing: 10) {
            // Avatar — tap to switch
            Button { selectedAccountID = account.id } label: {
                ZStack {
                    Circle().fill(isSelected ? theme.accentPrimary : theme.hoverBackground)
                    if !isSelected && account.profilePictureURL == nil {
                        Circle().strokeBorder(theme.divider, lineWidth: 1)
                    }

                    if let url = account.profilePictureURL {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill().clipShape(Circle())
                            } else {
                                Text(initial)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : theme.textSecondary)
                            }
                        }
                    } else {
                        Text(initial)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isSelected ? .white : theme.textSecondary)
                    }

                    if isSelected && account.profilePictureURL != nil {
                        Circle().strokeBorder(theme.accentPrimary, lineWidth: 2)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

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

            // Active indicator
            if isSelected {
                Circle()
                    .fill(theme.accentPrimary)
                    .frame(width: 6, height: 6)
            }

            // Sign out
            Button {
                authViewModel.signOut(account)
                if isSelected {
                    selectedAccountID = authViewModel.accounts.first?.id
                }
                // Return to onboarding when last account is removed
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
