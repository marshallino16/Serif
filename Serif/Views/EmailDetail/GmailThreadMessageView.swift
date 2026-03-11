import SwiftUI

struct GmailThreadMessageView: View {
    let message: GmailMessage
    let fromAddress: String
    var resolvedHTML: String?
    var onOpenLink: ((URL) -> Void)?
    @Environment(\.theme) private var theme
    @State private var showQuoted = false
    @State private var contentHeight: CGFloat = 60

    /// Cached result of `stripQuotedHTML` — computed once at init to avoid
    /// repeated regex work (10 passes) on every render cycle.
    private let cachedHTMLParts: (original: String, quoted: String?)

    init(message: GmailMessage, fromAddress: String, resolvedHTML: String? = nil, onOpenLink: ((URL) -> Void)? = nil) {
        self.message = message
        self.fromAddress = fromAddress
        self.resolvedHTML = resolvedHTML
        self.onOpenLink = onOpenLink

        let html = Self.computeFullHTML(message: message, resolvedHTML: resolvedHTML)
        self.cachedHTMLParts = Self.stripQuotedHTML(html)
    }

    private var sender: Contact { GmailDataTransformer.parseContact(message.from) }

    private var isSentByMe: Bool {
        guard !fromAddress.isEmpty else { return false }
        return sender.email.lowercased() == fromAddress.lowercased()
    }

    /// The raw HTML for this message — use resolved (inline images) if available.
    private var fullHTML: String {
        Self.computeFullHTML(message: message, resolvedHTML: resolvedHTML)
    }

    /// Compute the full HTML from message parts (static for use in init).
    private static func computeFullHTML(message: GmailMessage, resolvedHTML: String?) -> String {
        if let resolved = resolvedHTML, !resolved.isEmpty { return resolved }
        if let html = message.htmlBody, !html.isEmpty { return html }
        if let plain = message.plainBody, !plain.isEmpty { return "<p>\(plain)</p>" }
        let body = message.body
        return body.isEmpty ? "" : "<p>\(body)</p>"
    }

    /// Which HTML to actually render: stripped or full.
    private var renderedHTML: String {
        if showQuoted || cachedHTMLParts.quoted == nil {
            return fullHTML
        }
        return cachedHTMLParts.original
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isSentByMe { Spacer(minLength: 60) }

            if !isSentByMe {
                AvatarView(initials: sender.initials, color: sender.avatarColor, size: 28,
                           avatarURL: sender.avatarURL, senderDomain: sender.domain)
            }

            VStack(alignment: isSentByMe ? .trailing : .leading, spacing: 4) {
                if !isSentByMe {
                    Text(sender.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }

                // Bubble
                VStack(alignment: .leading, spacing: 0) {
                    HTMLEmailView(html: renderedHTML, contentHeight: $contentHeight, onOpenLink: onOpenLink)
                        .frame(height: contentHeight)

                    if cachedHTMLParts.quoted != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showQuoted.toggle()
                            }
                        } label: {
                            Text(showQuoted ? "Hide" : "···")
                                .font(.system(size: showQuoted ? 10 : 14, weight: showQuoted ? .medium : .bold))
                                .foregroundColor(theme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(theme.hoverBackground))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                        .padding(.leading, 4)
                    }
                }
                .padding(10)
                .frame(maxWidth: 500, alignment: .leading)
                .background(
                    isSentByMe
                        ? theme.accentPrimary.opacity(0.12)
                        : theme.cardBackground
                )
                .clipShape(ChatBubbleShape(isSentByMe: isSentByMe))

                if let date = message.date {
                    Text(date.formattedRelative)
                        .font(.system(size: 10))
                        .foregroundColor(theme.textTertiary)
                }
            }

            if !isSentByMe { Spacer(minLength: 60) }
        }
    }

    // MARK: - HTML quote stripping

    /// Removes quoted/replied content from HTML, returning (original, quoted?).
    /// Detects Gmail, Outlook, Apple Mail, and generic patterns.
    static func stripQuotedHTML(_ html: String) -> (original: String, quoted: String?) {
        // --- 1. Gmail: <div class="gmail_quote"> or <div class="gmail_quote_container"> ---
        if let range = html.range(of: #"<div\s+class\s*=\s*"[^"]*gmail_quote[^"]*""#,
                                  options: .regularExpression) {
            // Walk backwards to find the start of the containing element
            let before = String(html[html.startIndex..<range.lowerBound])
            let after = String(html[range.lowerBound...])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (before, after)
            }
        }

        // --- 2. Outlook: <div id="divRplyFwdMsg"> or <div id="appendonsend"> ---
        for pattern in [
            #"<div\s+id\s*=\s*"divRplyFwdMsg""#,
            #"<div\s+id\s*=\s*"appendonsend""#,
        ] {
            if let range = html.range(of: pattern, options: .regularExpression) {
                let before = String(html[html.startIndex..<range.lowerBound])
                let after = String(html[range.lowerBound...])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (before, after)
                }
            }
        }

        // --- 2b. Outlook border-top separator: only if followed by "De"/"From" header ---
        if let range = html.range(of: #"<div\s+style\s*=\s*"[^"]*border-top\s*:\s*solid[^"]*"[^>]*>"#,
                                  options: .regularExpression) {
            // Check that "De" or "From" header appears shortly after the separator
            let afterStart = range.lowerBound
            let lookAhead = String(html[afterStart..<html.index(afterStart, offsetBy: min(500, html.distance(from: afterStart, to: html.endIndex)))])
            if lookAhead.range(of: #"(De|From)(\s|&nbsp;|;)*\s*:"#, options: .regularExpression) != nil {
                let before = String(html[html.startIndex..<range.lowerBound])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (before, String(html[range.lowerBound...]))
                }
            }
        }

        // --- 3. "On ... wrote:" / "Le ... a écrit" in an <div class="gmail_attr"> or loose text ---
        let attrPatterns = [
            #"<div[^>]*class\s*=\s*"[^"]*gmail_attr[^"]*"[^>]*>.*?</div>\s*<blockquote"#,
            #"On\s.+wrote\s*:"#,
            #"Le\s.+a\s+(é|e)crit\s*:"#,
        ]
        for pattern in attrPatterns {
            if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let before = String(html[html.startIndex..<range.lowerBound])
                let after = String(html[range.lowerBound...])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (before, after)
                }
            }
        }

        // --- 4. Outlook FR/EN header block: "De :" / "From:" followed by "Envoyé"/"Sent" ---
        let headerPatterns = [
            #"<b>De(\s|&nbsp;)*:</\s*b>"#,
            #"<b>From(\s|&nbsp;)*:</\s*b>"#,
            #"-----\s*Original Message\s*-----"#,
            #"-----\s*Message d['']origine\s*-----"#,
            #"---------- Forwarded message ----------"#,
        ]
        for pattern in headerPatterns {
            if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let before = String(html[html.startIndex..<range.lowerBound])
                let after = String(html[range.lowerBound...])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (before, after)
                }
            }
        }

        // --- 5. Generic <blockquote> as last resort (only if it's a big trailing block) ---
        // Find the last <blockquote that takes up a significant portion of the HTML
        if let range = html.range(of: #"<blockquote[\s>]"#, options: [.regularExpression, .backwards]) {
            let before = String(html[html.startIndex..<range.lowerBound])
            let afterLen = html[range.lowerBound...].count
            // Only strip if the blockquote is at least 30% of the content
            if afterLen > html.count * 3 / 10 &&
               !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (before, String(html[range.lowerBound...]))
            }
        }

        return (html, nil)
    }
}

// MARK: - Chat bubble shape

private struct ChatBubbleShape: Shape {
    let isSentByMe: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 14
        let tail: CGFloat = 4

        var path = Path()

        if isSentByMe {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                              control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tail))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - tail, y: rect.maxY),
                              control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                              control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                              control: CGPoint(x: rect.minX, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                              control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                              control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + tail, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - tail),
                              control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                              control: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}
