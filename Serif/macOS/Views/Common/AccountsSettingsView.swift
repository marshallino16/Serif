import SwiftUI
import BlossomColorPicker

struct AccountsSettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Binding var selectedAccountID: String?
    @AppStorage("isSignedIn") private var isSignedIn: Bool = true
    @Environment(\.theme) private var theme
    @State private var colorBindings: [String: Color] = [:]

    // Drag state
    @State private var draggingID: String?
    @State private var dragOffset: CGFloat = 0
    @State private var sourceIndex: Int?

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
                let rowHeight: CGFloat = 50
                VStack(spacing: 6) {
                    ForEach(Array(authViewModel.accounts.enumerated()), id: \.element.id) { index, account in
                        let isDragging = draggingID == account.id
                        let displacement = rowDisplacement(for: index, rowHeight: rowHeight)

                        accountRow(account, index: index)
                            .zIndex(isDragging ? 10 : 0)
                            .scaleEffect(isDragging ? 1.03 : 1.0)
                            .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: 8, y: 2)
                            .offset(y: isDragging ? dragOffset : displacement)
                            .animation(isDragging ? nil : .easeInOut(duration: 0.2), value: dragOffset)
                            .animation(.easeInOut(duration: 0.2), value: displacement)
                            .animation(.easeInOut(duration: 0.2), value: draggingID)
                            .gesture(
                                authViewModel.accounts.count > 1
                                ? DragGesture()
                                    .onChanged { value in
                                        if draggingID == nil {
                                            draggingID = account.id
                                            sourceIndex = index
                                        }
                                        dragOffset = value.translation.height
                                    }
                                    .onEnded { _ in
                                        commitReorder(rowHeight: rowHeight)
                                    }
                                : nil
                            )
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

    // MARK: - Drag helpers

    /// How many positions the dragged item has moved from its source.
    private var draggedSteps: Int {
        guard sourceIndex != nil else { return 0 }
        let rowHeight: CGFloat = 56 // row height + spacing
        return Int((dragOffset / rowHeight).rounded())
    }

    /// Vertical displacement for non-dragged rows to make room.
    private func rowDisplacement(for index: Int, rowHeight: CGFloat) -> CGFloat {
        guard let src = sourceIndex, draggingID != nil, draggingID != authViewModel.accounts[index].id else { return 0 }
        let dest = src + draggedSteps
        let step: CGFloat = rowHeight + 6 // row + spacing
        if src < dest {
            // Dragging down: rows between src+1...dest shift up
            return (index > src && index <= dest) ? -step : 0
        } else {
            // Dragging up: rows between dest...src-1 shift down
            return (index >= dest && index < src) ? step : 0
        }
    }

    private func commitReorder(rowHeight: CGFloat) {
        guard let src = sourceIndex else {
            draggingID = nil
            dragOffset = 0
            sourceIndex = nil
            return
        }
        let dest = max(0, min(authViewModel.accounts.count - 1, src + draggedSteps))
        if src != dest {
            var all = AccountStore.shared.accounts
            let account = all.remove(at: src)
            all.insert(account, at: dest)
            AccountStore.shared.accounts = all
            authViewModel.reloadAccounts()
        }
        draggingID = nil
        dragOffset = 0
        sourceIndex = nil
    }

    // MARK: - Row

    private func accountRow(_ account: GmailAccount, index: Int) -> some View {
        let isSelected = account.id == selectedAccountID
            || (selectedAccountID == nil && account.id == authViewModel.accounts.first?.id)
        let isFirst = index == 0

        return HStack(spacing: 10) {
            // Drag handle
            if authViewModel.accounts.count > 1 {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.textTertiary.opacity(0.5))
                    .frame(width: 18)
                    .contentShape(.rect)
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
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                    if isFirst {
                        Text("Default")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(theme.accentPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(theme.accentPrimary.opacity(0.12))
                            .cornerRadius(3)
                    }
                }
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.08))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.red.opacity(0.2), lineWidth: 1))
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
