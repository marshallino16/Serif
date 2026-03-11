import Foundation

extension String {
    var strippingHTML: String {
        var result = self
        // Remove style/script blocks first
        result = result.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>",  with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        // Replace block tags with newlines
        result = result.replacingOccurrences(of: "<br\\s*/?>",  with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<p[^>]*>",    with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>",         with: "")
        result = result.replacingOccurrences(of: "<div[^>]*>",  with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</div>",       with: "")
        // Strip remaining tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&nbsp;",  with: " ")
        result = result.replacingOccurrences(of: "&lt;",    with: "<")
        result = result.replacingOccurrences(of: "&gt;",    with: ">")
        result = result.replacingOccurrences(of: "&amp;",   with: "&")
        result = result.replacingOccurrences(of: "&quot;",  with: "\"")
        result = result.replacingOccurrences(of: "&#39;",   with: "'")
        // Collapse multiple blank lines
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cleans email body text for AI consumption: strips HTML, decodes entities,
    /// removes quoted replies and signature noise, truncates to `maxLength`.
    ///
    /// Shared by QuickReplyService and SummaryService.
    /// SummaryService still has its own copy — migrate it to use this method next.
    func cleanedForAI(maxLength: Int = 500) -> String {
        var text = self

        // Strip HTML tags
        if text.contains("<") {
            text = text.replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression
            )
        }

        // Decode hex numeric HTML entities (&#x27; etc.)
        if let regex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);") {
            let mutable = NSMutableString(string: text)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                if let range = Range(match.range(at: 1), in: text),
                   let code = UInt32(text[range], radix: 16),
                   let scalar = Unicode.Scalar(code) {
                    mutable.replaceCharacters(in: match.range, with: String(scalar))
                }
            }
            text = mutable as String
        }

        // Decode decimal numeric HTML entities (&#39; &#8203; etc.)
        if let regex = try? NSRegularExpression(pattern: "&#([0-9]+);") {
            let mutable = NSMutableString(string: text)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                if let range = Range(match.range(at: 1), in: text),
                   let code = UInt32(text[range]),
                   let scalar = Unicode.Scalar(code) {
                    mutable.replaceCharacters(in: match.range, with: String(scalar))
                }
            }
            text = mutable as String
        }

        // Decode named HTML entities
        let entities: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&rsquo;": "\u{2019}",
            "&lsquo;": "\u{2018}", "&rdquo;": "\u{201D}", "&ldquo;": "\u{201C}",
            "&ndash;": "\u{2013}", "&mdash;": "\u{2014}", "&hellip;": "\u{2026}",
            "&euro;": "\u{20AC}", "&copy;": "\u{00A9}", "&reg;": "\u{00AE}",
            "&trade;": "\u{2122}", "&bull;": "\u{2022}"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        // Split into lines and filter noise
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if line.hasPrefix(">") { return false }
                let lower = line.lowercased()
                let noise = [
                    "sent from my iphone", "sent from my ipad",
                    "sent from outlook", "sent from mail",
                    "get outlook for", "unsubscribe",
                    "view this email in your browser",
                    "click here to unsubscribe",
                    "this email was sent to",
                    "if you no longer wish",
                    "-- ", "---", "___"
                ]
                return !noise.contains(where: { lower.hasPrefix($0) || lower == $0 })
            }

        let cleaned = lines.joined(separator: "\n")

        // Collapse excessive whitespace
        let collapsed = cleaned
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(collapsed.prefix(maxLength))
    }
}
