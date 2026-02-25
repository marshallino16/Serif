import SwiftUI

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String

    // MARK: - Backgrounds
    let sidebarBackground: Color
    let listBackground: Color
    let detailBackground: Color
    let cardBackground: Color
    let selectedCardBackground: Color
    let hoverBackground: Color
    let searchBarBackground: Color

    // MARK: - Accents
    let accentPrimary: Color
    let accentSecondary: Color

    // MARK: - Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textInverse: Color

    // MARK: - Borders & Dividers
    let border: Color
    let divider: Color

    // MARK: - Semantic
    let unreadIndicator: Color
    let attachmentBackground: Color
    let avatarRing: Color
    let destructive: Color

    // MARK: - Components
    let buttonPrimary: Color
    let buttonSecondary: Color
    let inputBackground: Color
    let tagBackground: Color

    static func == (lhs: Theme, rhs: Theme) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
