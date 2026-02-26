import Foundation
import AppKit

/// Handles all unsubscribe interactions: RFC 8058 one-click POST, browser URL, mailto, and body link scanning.
@MainActor
final class UnsubscribeService {
    static let shared = UnsubscribeService()
    private init() {}

    // MARK: - Perform unsubscribe

    func unsubscribe(url: URL, oneClick: Bool) async {
        if oneClick && (url.scheme == "https" || url.scheme == "http") {
            await performOneClickPost(url: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// RFC 8058: POST with body "List-Unsubscribe=One-Click"
    private func performOneClickPost(url: URL) async {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "List-Unsubscribe=One-Click".data(using: .utf8)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Body link scanning

    /// Scans an HTML (or plain-text) email body for the first unsubscribe link.
    /// Returns nil if no link is found.
    static func extractBodyUnsubscribeURL(from html: String) -> URL? {
        // Pattern: href="https://..." within an <a> tag whose visible text contains an unsubscribe keyword
        // We match the href value, then verify the nearby text contains the keyword.
        guard let regex = try? NSRegularExpression(
            pattern: #"href=["'](https?://[^"'\s>]+)["'][^>]*>(?:[^<]{0,300})(?:unsubscribe|opt.out|désabonner|se désinscrire|remove me)"#,
            options: .caseInsensitive
        ) else { return nil }

        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let urlRange = Range(match.range(at: 1), in: html)
        else { return nil }

        return URL(string: String(html[urlRange]))
    }
}
