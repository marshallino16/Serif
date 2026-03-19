import SwiftUI

struct iOSThemePickerView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                darkSection
                lightSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(themeManager.currentTheme.detailBackground)
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.theme, themeManager.currentTheme)
    }

    // MARK: - Sections

    private var darkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Dark")
            themeCard(themes: themeManager.availableThemes.filter { !$0.isLight })
        }
    }

    private var lightSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Light")
            themeCard(themes: themeManager.availableThemes.filter { $0.isLight })
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(themeManager.currentTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.bottom, 4)
    }

    private func themeCard(themes: [Theme]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(themes.enumerated()), id: \.element.id) { index, t in
                if index > 0 {
                    Divider().padding(.leading, 16)
                }
                themeRow(t)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(themeManager.currentTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func themeRow(_ t: Theme) -> some View {
        let currentTheme = themeManager.currentTheme
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                themeManager.selectTheme(t)
            }
        } label: {
            HStack(spacing: 12) {
                // Color preview
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(t.sidebarBackground)
                        .frame(width: 12, height: 24)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(t.listBackground)
                        .frame(width: 12, height: 24)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(t.detailBackground)
                        .frame(width: 12, height: 24)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(currentTheme.border, lineWidth: 1)
                )

                Text(t.name)
                    .foregroundColor(currentTheme.textPrimary)

                Spacer()

                if currentTheme.id == t.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(currentTheme.accentPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
