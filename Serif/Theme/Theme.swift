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

    /// Whether this theme has a light appearance (based on detail background luminance).
    var isLight: Bool {
        guard let c = NSColor(detailBackground).usingColorSpace(.sRGB) else { return false }
        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return lum > 0.5
    }

    static func == (lhs: Theme, rhs: Theme) -> Bool {
        lhs.id == rhs.id
        && lhs.sidebarBackground == rhs.sidebarBackground
        && lhs.listBackground == rhs.listBackground
        && lhs.detailBackground == rhs.detailBackground
        && lhs.cardBackground == rhs.cardBackground
        && lhs.accentPrimary == rhs.accentPrimary
        && lhs.accentSecondary == rhs.accentSecondary
        && lhs.textPrimary == rhs.textPrimary
        && lhs.textSecondary == rhs.textSecondary
        && lhs.textTertiary == rhs.textTertiary
        && lhs.buttonPrimary == rhs.buttonPrimary
        && lhs.destructive == rhs.destructive
    }

    /// All customizable color property names, grouped by category.
    static let colorGroups: [(name: String, keys: [String])] = [
        ("Backgrounds", ["sidebarBackground", "listBackground", "detailBackground", "cardBackground", "selectedCardBackground", "hoverBackground", "searchBarBackground"]),
        ("Accents", ["accentPrimary", "accentSecondary"]),
        ("Text", ["textPrimary", "textSecondary", "textTertiary", "textInverse"]),
        ("Borders", ["border", "divider"]),
        ("Semantic", ["unreadIndicator", "destructive", "avatarRing", "attachmentBackground"]),
        ("Components", ["buttonPrimary", "buttonSecondary", "inputBackground", "tagBackground"]),
    ]

    /// Returns the Color for a given property key name.
    func color(for key: String) -> Color {
        switch key {
        case "sidebarBackground": return sidebarBackground
        case "listBackground": return listBackground
        case "detailBackground": return detailBackground
        case "cardBackground": return cardBackground
        case "selectedCardBackground": return selectedCardBackground
        case "hoverBackground": return hoverBackground
        case "searchBarBackground": return searchBarBackground
        case "accentPrimary": return accentPrimary
        case "accentSecondary": return accentSecondary
        case "textPrimary": return textPrimary
        case "textSecondary": return textSecondary
        case "textTertiary": return textTertiary
        case "textInverse": return textInverse
        case "border": return border
        case "divider": return divider
        case "unreadIndicator": return unreadIndicator
        case "attachmentBackground": return attachmentBackground
        case "avatarRing": return avatarRing
        case "destructive": return destructive
        case "buttonPrimary": return buttonPrimary
        case "buttonSecondary": return buttonSecondary
        case "inputBackground": return inputBackground
        case "tagBackground": return tagBackground
        default: return .clear
        }
    }

    /// Creates a new Theme from this one with the given color overrides applied.
    func applying(overrides: [String: String]) -> Theme {
        func c(_ key: String, fallback: Color) -> Color {
            if let hex = overrides[key] { return Color(hex: hex) }
            return fallback
        }
        return Theme(
            id: id, name: name, icon: icon,
            sidebarBackground: c("sidebarBackground", fallback: sidebarBackground),
            listBackground: c("listBackground", fallback: listBackground),
            detailBackground: c("detailBackground", fallback: detailBackground),
            cardBackground: c("cardBackground", fallback: cardBackground),
            selectedCardBackground: c("selectedCardBackground", fallback: selectedCardBackground),
            hoverBackground: c("hoverBackground", fallback: hoverBackground),
            searchBarBackground: c("searchBarBackground", fallback: searchBarBackground),
            accentPrimary: c("accentPrimary", fallback: accentPrimary),
            accentSecondary: c("accentSecondary", fallback: accentSecondary),
            textPrimary: c("textPrimary", fallback: textPrimary),
            textSecondary: c("textSecondary", fallback: textSecondary),
            textTertiary: c("textTertiary", fallback: textTertiary),
            textInverse: c("textInverse", fallback: textInverse),
            border: c("border", fallback: border),
            divider: c("divider", fallback: divider),
            unreadIndicator: c("unreadIndicator", fallback: unreadIndicator),
            attachmentBackground: c("attachmentBackground", fallback: attachmentBackground),
            avatarRing: c("avatarRing", fallback: avatarRing),
            destructive: c("destructive", fallback: destructive),
            buttonPrimary: c("buttonPrimary", fallback: buttonPrimary),
            buttonSecondary: c("buttonSecondary", fallback: buttonSecondary),
            inputBackground: c("inputBackground", fallback: inputBackground),
            tagBackground: c("tagBackground", fallback: tagBackground)
        )
    }

    /// Human-readable label for a color property key.
    static func label(for key: String) -> String {
        switch key {
        case "sidebarBackground": return "Sidebar"
        case "listBackground": return "List"
        case "detailBackground": return "Detail"
        case "cardBackground": return "Card"
        case "selectedCardBackground": return "Selected Card"
        case "hoverBackground": return "Hover"
        case "searchBarBackground": return "Search Bar"
        case "accentPrimary": return "Primary"
        case "accentSecondary": return "Secondary"
        case "textPrimary": return "Primary"
        case "textSecondary": return "Secondary"
        case "textTertiary": return "Tertiary"
        case "textInverse": return "Inverse"
        case "border": return "Border"
        case "divider": return "Divider"
        case "unreadIndicator": return "Unread"
        case "attachmentBackground": return "Attachment"
        case "avatarRing": return "Avatar Ring"
        case "destructive": return "Destructive"
        case "buttonPrimary": return "Primary"
        case "buttonSecondary": return "Secondary"
        case "inputBackground": return "Input"
        case "tagBackground": return "Tag"
        default: return key
        }
    }
}

// MARK: - Color Extension

extension Color {
    /// Converts this Color to a hex string (#RRGGBB).
    var hexString: String {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

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
