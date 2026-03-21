import Foundation

/// Formats quoted email content for replies and forwards, matching Gmail's behavior.
enum QuoteFormatter {

    enum QuoteStyle: String {
        case gmail       // "On [date], [name] <[email]> wrote:" with gmail_quote div
        case blockquote  // Traditional blockquote with border-left
        case noQuote     // No quoting (include original without wrapper)
    }

    /// Returns the user's preferred quote style from settings.
    static var preferredStyle: QuoteStyle {
        let raw = UserDefaults.standard.string(forKey: "quoteStyle") ?? "gmail"
        return QuoteStyle(rawValue: raw) ?? .gmail
    }

    /// Formats the original email body for inclusion in a reply.
    static func formatReplyQuote(
        senderName: String,
        senderEmail: String,
        date: Date,
        originalHTML: String,
        style: QuoteStyle? = nil
    ) -> String {
        let effectiveStyle = style ?? preferredStyle
        switch effectiveStyle {
        case .gmail:
            return gmailQuote(senderName: senderName, senderEmail: senderEmail, date: date, body: originalHTML)
        case .blockquote:
            return blockQuote(senderName: senderName, body: originalHTML)
        case .noQuote:
            return originalHTML
        }
    }

    /// Formats the original email body for inclusion in a forward.
    static func formatForwardQuote(
        senderName: String,
        senderEmail: String,
        date: Date,
        to: String,
        subject: String,
        originalHTML: String
    ) -> String {
        let dateStr = formattedDate(date)
        let header = """
        ---------- Forwarded message ---------<br>
        From: <b>\(escaped(senderName))</b> &lt;\(escaped(senderEmail))&gt;<br>
        Date: \(dateStr)<br>
        Subject: \(escaped(subject))<br>
        To: \(escaped(to))<br>
        """
        return "<br><br><div class=\"gmail_quote\">\(header)<br>\(originalHTML)</div>"
    }

    // MARK: - Private

    private static func gmailQuote(senderName: String, senderEmail: String, date: Date, body: String) -> String {
        let dateStr = formattedDate(date)
        let nameDisplay = senderName.isEmpty ? senderEmail : senderName
        let attr = "On \(dateStr), \(escaped(nameDisplay)) &lt;\(escaped(senderEmail))&gt; wrote:"
        return """
        <br><br>\
        <div class="gmail_quote">\
        <div dir="ltr" class="gmail_attr">\(attr)</div>\
        <blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex">\
        \(body)\
        </blockquote>\
        </div>
        """
    }

    private static func blockQuote(senderName: String, body: String) -> String {
        return "<br><br><blockquote style='border-left:2px solid #ccc;margin-left:4px;padding-left:8px;color:#555;'><p><b>\(escaped(senderName))</b> wrote:</p>\(body)</blockquote>"
    }

    private static func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
