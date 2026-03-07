import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class SummaryService {
    static let shared = SummaryService()

    private var cache: [String: String] = [:]

    private init() {}

    func cachedSummary(for email: Email) -> String? {
        guard let key = cacheKey(for: email) else { return nil }
        return cache[key]
    }

    func summary(for email: Email) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                if let key = cacheKey(for: email), let cached = cache[key] {
                    continuation.yield(cached)
                    continuation.finish()
                    return
                }

                if #available(macOS 26.0, *) {
                    #if canImport(FoundationModels)
                    await generateWithFoundationModels(email: email, continuation: continuation)
                    #else
                    yieldFallback(email: email, continuation: continuation)
                    #endif
                } else {
                    yieldFallback(email: email, continuation: continuation)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func generateWithFoundationModels(email: Email, continuation: AsyncStream<String>.Continuation) async {
        do {
            let instructions = Instructions("""
            You are an email assistant inside a macOS email client. \
            The user is hovering over an email and wants a quick glanceable summary. \
            Rules:
            - Write 2-3 short sentences max.
            - Lead with the key intent or action requested, not a description of the email.
            - If there's a deadline, date, amount, or link, mention it.
            - If the email is a newsletter/promo, say what it's about in one line.
            - If it's a reply thread, focus on the latest message only.
            - Never start with "This email..." or "The sender...". Be direct.
            - Use the same language as the email body.
            - Strip any signature, disclaimer or legal notice from consideration.
            """)
            let session = LanguageModelSession(instructions: instructions)

            var context = "From: \(email.sender.name)"
            if !email.recipients.isEmpty {
                let to = email.recipients.prefix(3).map(\.name).joined(separator: ", ")
                context += "\nTo: \(to)"
            }
            context += "\nSubject: \(email.subject)"
            context += "\nDate: \(email.date.formatted(date: .abbreviated, time: .shortened))"
            if email.hasAttachments {
                let names = email.attachments.prefix(3).map(\.name).joined(separator: ", ")
                context += "\nAttachments: \(names)"
            }

            let body = cleanedPreview(from: email)
            let prompt = """
            \(context)

            \(body)
            """

            var accumulated = ""
            let response = session.streamResponse(to: prompt)
            for try await snapshot in response {
                accumulated = snapshot.content
                continuation.yield(accumulated)
            }

            if let key = cacheKey(for: email) {
                cache[key] = accumulated
            }
            continuation.finish()
        } catch {
            yieldFallback(email: email, continuation: continuation)
        }
    }
    #endif

    private func yieldFallback(email: Email, continuation: AsyncStream<String>.Continuation) {
        let fallback = cleanedPreview(from: email)
        if let key = cacheKey(for: email) {
            cache[key] = fallback
        }
        continuation.yield(fallback)
        continuation.finish()
    }

    private func cleanedPreview(from email: Email) -> String {
        var text = email.body.isEmpty ? email.preview : email.body

        // Strip HTML tags
        if text.contains("<") {
            text = text.replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression
            )
        }

        // Decode numeric HTML entities (&#39; &#8203; &#x27; etc.)
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
                // Skip quoted replies
                if line.hasPrefix(">") { return false }
                // Skip common signatures
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

        // Collapse multiple whitespace/newlines
        let collapsed = cleaned
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(collapsed.prefix(500))
    }

    private func cacheKey(for email: Email) -> String? {
        email.gmailMessageID ?? email.id.uuidString
    }
}
