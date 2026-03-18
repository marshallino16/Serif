import Foundation

// MARK: - Model

struct CalendarInvite: Equatable {
    let summary: String
    let dateText: String
    let location: String?
    let organizer: String?
    var acceptURL: URL?
    var declineURL: URL?
    var maybeURL: URL?
    var rsvpStatus: RSVPStatus = .pending

    enum RSVPStatus: String, Equatable { case accepted, declined, maybe, pending }
}

// MARK: - Parser

enum CalendarInviteParser {

    /// Detects a Google Calendar invitation from the HTML body.
    /// Returns nil if no RSVP URLs are found (not a calendar invite).
    static func parse(html: String, subject: String, sender: String) -> CalendarInvite? {
        let urls = extractRSVPURLs(from: html)
        // No RSVP URLs → not a calendar invite
        guard urls.accept != nil || urls.decline != nil || urls.maybe != nil else { return nil }

        let title = extractTitle(from: subject)
        let dateText = extractField(label: "When|Quand|Wann|Cuando", from: html) ?? ""
        let location = extractField(label: "Where|Où|Wo|Dónde|Location|Joining info|Informations de connexion", from: html)
        let organizer = extractOrganizer(from: html) ?? cleanSenderName(sender)

        return CalendarInvite(
            summary: title,
            dateText: dateText,
            location: location,
            organizer: organizer,
            acceptURL: urls.accept,
            declineURL: urls.decline,
            maybeURL: urls.maybe
        )
    }

    /// Sends a silent GET to the RSVP URL. Returns true on 2xx.
    static func sendRSVP(url: URL) async -> Bool {
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Private

    /// Extracts RSVP URLs from HTML body (Google Calendar rst=1/2/3 pattern).
    private static func extractRSVPURLs(from html: String) -> (accept: URL?, decline: URL?, maybe: URL?) {
        let pattern = #"https?://(?:www\.)?calendar\.google\.com/calendar/event\?action=RESPOND[^"'\s<>]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return (nil, nil, nil)
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        var accept: URL?
        var decline: URL?
        var maybe: URL?

        for match in matches {
            guard let r = Range(match.range, in: html) else { continue }
            var urlString = String(html[r])
            urlString = urlString.replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: urlString) else { continue }

            if urlString.contains("rst=1") { accept = url }
            else if urlString.contains("rst=2") { decline = url }
            else if urlString.contains("rst=3") { maybe = url }
        }

        return (accept, decline, maybe)
    }

    /// Strips "Invitation:" / "Invitation :" prefix from subject to get the event title.
    private static func extractTitle(from subject: String) -> String {
        let prefixes = ["Invitation:", "Invitation :", "Invite:", "Invite :"]
        for prefix in prefixes {
            if subject.hasPrefix(prefix) {
                return subject.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return subject
    }

    /// Extracts a field value from Google Calendar HTML by label.
    /// Google uses patterns like `<b>When</b>` or table cells with the label followed by the value.
    private static func extractField(label: String, from html: String) -> String? {
        // Pattern 1: <b>Label</b> ... text content (up to next <b> or </td> or </div>)
        let pattern1 = #"<b>\s*(?:\#(label))\s*</b>\s*(?:</td>\s*<td[^>]*>)?\s*(.*?)(?=<b>|</td>|</div>|</tr>|<br\s*/?>)"#
        if let value = firstMatch(pattern: pattern1, in: html, group: 2) {
            let clean = stripHTML(value)
            if !clean.isEmpty { return clean }
        }

        // Pattern 2: td/div with label, next td/div with value
        let pattern2 = #"(?:\#(label))\s*:?\s*</(?:td|div|span|b)>\s*</td>\s*<td[^>]*>\s*(.*?)\s*</td>"#
        if let value = firstMatch(pattern: pattern2, in: html, group: 2) {
            let clean = stripHTML(value)
            if !clean.isEmpty { return clean }
        }

        return nil
    }

    /// Tries to find the organizer name from HTML (Google Calendar patterns).
    private static func extractOrganizer(from html: String) -> String? {
        // Look for "Organizer" / "Organisateur" field
        let pattern = #"(?:Organizer|Organisateur|Organizado por)\s*:?\s*</(?:b|td|div|span)>\s*(?:</td>\s*<td[^>]*>)?\s*(.*?)(?=<|$)"#
        if let value = firstMatch(pattern: pattern, in: html, group: 1) {
            let clean = stripHTML(value)
            if !clean.isEmpty { return clean }
        }
        return nil
    }

    /// Extracts display name from "Name <email>" format.
    private static func cleanSenderName(_ sender: String) -> String {
        if let open = sender.firstIndex(of: "<") {
            return String(sender[sender.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        }
        return sender
    }

    private static func firstMatch(pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let r = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[r])
    }

    /// Strips HTML tags and decodes common entities.
    private static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        // Collapse whitespace
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
