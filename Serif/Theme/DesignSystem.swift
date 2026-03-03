import SwiftUI

// MARK: - Typography

extension Font {
    /// 14pt semibold — section titles, card headers
    static let serifTitle = Font.system(size: 14, weight: .semibold)
    /// 13pt regular — primary body text
    static let serifBody = Font.system(size: 13)
    /// 12pt medium — field labels, button text
    static let serifLabel = Font.system(size: 12, weight: .medium)
    /// 12pt regular — secondary/caption text
    static let serifCaption = Font.system(size: 12)
    /// 11pt regular — small text, tertiary info
    static let serifSmall = Font.system(size: 11)
    /// 11pt medium — small emphasized text
    static let serifSmallMedium = Font.system(size: 11, weight: .medium)
    /// 12pt monospaced medium — code, sizes, counts
    static let serifMono = Font.system(size: 12, weight: .medium, design: .monospaced)
    /// 10pt semibold — badges
    static let serifBadge = Font.system(size: 10, weight: .semibold)
}

// MARK: - Helpers

extension Int {
    /// Returns self if non-zero, otherwise the given default.
    func nonZeroOr(_ fallback: Int) -> Int { self != 0 ? self : fallback }
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}
