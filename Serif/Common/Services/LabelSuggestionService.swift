import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct LabelSuggestion: Equatable {
    let name: String
    let isNew: Bool
}

@MainActor
final class LabelSuggestionService {
    static let shared = LabelSuggestionService()

    private var cache: [String: [LabelSuggestion]] = [:]

    private init() {}

    func cachedSuggestions(for email: Email) -> [LabelSuggestion]? {
        guard let key = cacheKey(for: email) else { return nil }
        return cache[key]
    }

    func generateSuggestions(for email: Email, existingLabels: [GmailLabel]) async -> [LabelSuggestion] {
        if let key = cacheKey(for: email), let cached = cache[key] {
            return cached
        }

        if #available(macOS 26.0, iOS 26.0, *) {
            #if canImport(FoundationModels)
            return await generateWithFoundationModels(email: email, existingLabels: existingLabels)
            #else
            return []
            #endif
        } else {
            return []
        }
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private func generateWithFoundationModels(email: Email, existingLabels: [GmailLabel]) async -> [LabelSuggestion] {
        do {
            let userLabels = existingLabels
                .filter { !$0.isSystemLabel }
                .map(\.displayName)

            let labelList = userLabels.isEmpty
                ? "None yet."
                : userLabels.joined(separator: ", ")

            let preview = String(email.preview.prefix(200))

            let instructions = Instructions("""
            You are a label suggestion assistant inside a macOS email client. \
            Given an email and existing user labels, suggest 1 to 3 labels to apply. \
            Rules:
            - Prefer existing labels. Only suggest a new label if no existing label fits.
            - Return a JSON array, nothing else: [{"name": "Label", "isNew": false}]
            - Keep names short (1-3 words), capitalized, in English.
            - Do not wrap the JSON in markdown fences or add any extra text.
            """)
            let session = LanguageModelSession(instructions: instructions)

            let prompt = """
            Existing labels: \(labelList)

            From: \(email.sender.name) <\(email.sender.email)>
            Subject: \(email.subject)
            Preview: \(preview)
            """

            let response = try await session.respond(to: prompt)
            let suggestions = parseSuggestions(from: response.content, existingLabels: userLabels)

            if let key = cacheKey(for: email) {
                cache[key] = suggestions
            }
            return suggestions
        } catch {
            return []
        }
    }
    #endif

    private func parseSuggestions(from text: String, existingLabels: [String]) -> [LabelSuggestion] {
        // Strip markdown fences if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.range(of: "```json") ?? cleaned.range(of: "```") {
            cleaned = String(cleaned[start.upperBound...])
        }
        if let end = cleaned.range(of: "```", options: .backwards) {
            cleaned = String(cleaned[..<end.lowerBound])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract JSON array from the text
        guard let startBracket = cleaned.firstIndex(of: "["),
              let endBracket = cleaned.lastIndex(of: "]") else {
            return []
        }
        let jsonString = String(cleaned[startBracket...endBracket])

        guard let data = jsonString.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let existingNamesLowered = Set(existingLabels.map { $0.lowercased() })

        return items.prefix(3).compactMap { item -> LabelSuggestion? in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            let isNew = !existingNamesLowered.contains(name.lowercased())
            return LabelSuggestion(name: name, isNew: isNew)
        }
    }

    private func cacheKey(for email: Email) -> String? {
        email.gmailMessageID ?? email.id.uuidString
    }
}
