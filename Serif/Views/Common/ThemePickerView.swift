import SwiftUI

struct ThemePickerView: View {
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.theme) private var theme
    @State private var showCustomize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                ForEach(themeManager.availableThemes) { t in
                    ThemePreviewCard(
                        theme: t,
                        isSelected: themeManager.selectedBaseID == t.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            themeManager.selectTheme(t)
                        }
                    }
                }
            }

            Divider().background(theme.divider)

            // Customize toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showCustomize.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 11))
                    Text("Customize colors")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if themeManager.hasOverrides {
                        Text("\(themeManager.currentOverrides.count) modified")
                            .font(.system(size: 10))
                            .foregroundColor(theme.textTertiary)
                    }
                    Image(systemName: showCustomize ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(theme.accentPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showCustomize {
                customizeSection
            }
        }
        .padding(20)
        .background(theme.cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }

    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if themeManager.hasOverrides {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            themeManager.resetOverrides()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                            Text("Reset all")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(theme.destructive)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(Theme.colorGroups, id: \.name) { group in
                colorGroup(group.name, keys: group.keys)
            }
        }
    }

    private func colorGroup(_ name: String, keys: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.textSecondary)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    ColorRowView(key: key, themeManager: themeManager)
                }
            }
        }
    }
}

struct ColorRowView: View {
    let key: String
    @ObservedObject var themeManager: ThemeManager

    private var isOverridden: Bool {
        themeManager.currentOverrides[key] != nil
    }

    private var baseTheme: Theme {
        themeManager.availableThemes.first { $0.id == themeManager.selectedBaseID } ?? .midnight
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { themeManager.currentTheme.color(for: key) },
            set: { newColor in
                let hex = newColor.hexString
                let baseHex = baseTheme.color(for: key).hexString
                if hex == baseHex {
                    themeManager.removeOverride(key: key)
                } else {
                    themeManager.setOverride(key: key, hex: hex)
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.8)
                .frame(width: 22, height: 22)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1.5))

            Text(Theme.label(for: key))
                .font(.system(size: 11))
                .foregroundColor(isOverridden ? themeManager.currentTheme.accentPrimary : themeManager.currentTheme.textSecondary)
                .lineLimit(1)

            Spacer()

            if isOverridden {
                Button {
                    themeManager.removeOverride(key: key)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(themeManager.currentTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
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
