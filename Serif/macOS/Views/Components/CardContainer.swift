import SwiftUI

/// A view modifier that applies the standard settings-card styling:
/// padding, background, corner radius, and subtle drop shadow.
struct CardStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(theme.cardBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }
}

extension View {
    /// Wraps the view in a themed settings card.
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
