import SwiftUI

/// A plain toolbar-style icon button used across toolbars and headers.
///
/// Renders an SF Symbol inside a fixed-size hit target with `.buttonStyle(.plain)`.
struct IconButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 14
    var color: Color?
    var tooltip: String?
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(color ?? theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip ?? "")
    }
}
