import SwiftUI

struct iOSContentView: View {
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 48))
                .foregroundColor(themeManager.currentTheme.accentPrimary)
            Text("Serif")
                .font(.system(size: 24, weight: .bold))
            Text("iOS — Coming Soon")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.currentTheme.detailBackground)
        .environment(\.theme, themeManager.currentTheme)
    }
}
