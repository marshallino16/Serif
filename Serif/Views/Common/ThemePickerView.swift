import SwiftUI

struct ThemePickerView: View {
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                ForEach(themeManager.availableThemes) { t in
                    ThemePreviewCard(
                        theme: t,
                        isSelected: themeManager.currentTheme.id == t.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            themeManager.currentTheme = t
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(theme.cardBackground)
        .cornerRadius(12)
    }
}

struct ThemePreviewCard: View {
    let theme: Theme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Mini preview
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.detailBackground)
                    .frame(height: 48)
                    .overlay(
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.sidebarBackground)
                                .frame(width: 12)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.listBackground)
                                .frame(width: 20)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.detailBackground)
                                .overlay(
                                    VStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(theme.accentPrimary)
                                            .frame(height: 3)
                                            .padding(.horizontal, 4)
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(theme.textTertiary)
                                            .frame(height: 2)
                                            .padding(.horizontal, 6)
                                    }
                                )
                        }
                        .padding(4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? theme.accentPrimary : Color.clear, lineWidth: 2)
                    )

                HStack(spacing: 4) {
                    Image(systemName: theme.icon)
                        .font(.system(size: 10))
                    Text(theme.name)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isSelected ? theme.accentPrimary : theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}
