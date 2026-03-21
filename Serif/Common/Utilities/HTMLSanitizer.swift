import Foundation

/// Sanitizes HTML before sending emails to ensure proper display on all clients.
enum HTMLSanitizer {

    /// Strips theme-specific text colors from HTML so emails display with standard black text.
    /// Preserves explicitly chosen colors (red, blue, etc.) that differ from the theme default.
    /// - Parameters:
    ///   - html: The raw HTML from the editor
    ///   - themeTextColor: The hex color used by the current theme (e.g., "#FAFAFA" for Zinc)
    /// - Returns: Sanitized HTML safe for sending
    static func sanitizeForSend(_ html: String, themeTextColor: String) -> String {
        var result = html

        // 1. Remove any inline color that matches the theme text color (case-insensitive)
        // These are display-only colors from the editor, not intentional user choices
        let themeHex = themeTextColor.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let patterns = [
            "color:\\s*#\(themeHex)",                    // color: #fafafa
            "color:\\s*#\(themeHex.uppercased())",        // color: #FAFAFA
            "color:\\s*\(themeTextColor)",                // color: #FAFAFA (with #)
            "color:\\s*rgb\\(250,\\s*250,\\s*250\\)",     // color: rgb(250, 250, 250) for Zinc
            "color:\\s*rgb\\(255,\\s*255,\\s*255\\)",     // color: rgb(255, 255, 255) pure white
            "color:\\s*white",                            // color: white
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "color: #000000"
                )
            }
        }

        // 2. Also strip common "near-white" colors that would be invisible on white background
        // Common dark theme text colors across our themes
        let nearWhiteColors = [
            "#e6edf3", "#f8f8f2", "#eceff4", "#f0fdfa", "#f8e8f0",  // Various theme textPrimary
            "#cdd6f4", "#c0caf5", "#e8f0e4", "#e8e2ea", "#abb2bf",  // More theme colors
        ]
        for hex in nearWhiteColors {
            let hexClean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if let regex = try? NSRegularExpression(
                pattern: "color:\\s*#\(hexClean)",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "color: #000000"
                )
            }
        }

        return result
    }
}
