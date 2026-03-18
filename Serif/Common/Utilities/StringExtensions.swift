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
}
