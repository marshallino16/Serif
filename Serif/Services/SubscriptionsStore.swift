import Foundation
import Combine

// MARK: - URL validity cache (thread-safe)

private final class URLValidityCache: @unchecked Sendable {
    private var cache: [URL: Bool] = [:]
    private let lock = NSLock()

    func get(_ url: URL) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return cache[url]
    }
    func set(_ url: URL, valid: Bool) {
        lock.lock(); defer { lock.unlock() }
        cache[url] = valid
    }

    /// Performs a HEAD request and returns true if the server replies 2xx/3xx.
    func check(_ url: URL) async -> Bool {
        if let cached = get(url) { return cached }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 6

        let valid: Bool
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse {
            valid = (200...399).contains(http.statusCode)
        } else {
            valid = false
        }
        set(url, valid: valid)
        return valid
    }
}

// MARK: - SubscriptionsStore

/// Collects emails identified as mailing-list subscriptions by analysing every
/// loaded message in the background.  An HTTP HEAD check ensures the unsubscribe
/// URL is reachable before the email surfaces in the Subscriptions folder.
@MainActor
final class SubscriptionsStore: ObservableObject {
    static let shared = SubscriptionsStore()

    @Published private(set) var entries:     [Email] = []
    @Published private(set) var isAnalyzing: Bool    = false

    private var processedIDs = Set<String>()   // per-session dedup
    private let urlCache     = URLValidityCache()
    private var pendingCount = 0               // tracks concurrent analysis tasks

    private init() {}

    // MARK: - Analyze

    /// Call this whenever new emails are available.  Already-processed messages
    /// are skipped.  Eligible emails are those with a valid unsubscribeURL.
    func analyze(_ emails: [Email]) {
        let candidates = emails.filter { email in
            guard let id = email.gmailMessageID,
                  !processedIDs.contains(id),
                  email.unsubscribeURL != nil
            else { return false }
            return true
        }
        guard !candidates.isEmpty else { return }

        // Mark as seen immediately so concurrent calls don't re-process
        candidates.compactMap(\.gmailMessageID).forEach { processedIDs.insert($0) }

        pendingCount += 1
        isAnalyzing   = true

        Task {
            await withTaskGroup(of: (Email, Bool).self) { [urlCache] group in
                for email in candidates {
                    group.addTask {
                        guard let url = email.unsubscribeURL else { return (email, false) }
                        let valid = await urlCache.check(url)
                        return (email, valid)
                    }
                }
                for await (email, valid) in group {
                    guard valid else { continue }
                    if !entries.contains(where: { $0.id == email.id }) {
                        entries.append(email)
                    }
                }
            }
            entries.sort { $0.date > $1.date }

            pendingCount -= 1
            if pendingCount == 0 { isAnalyzing = false }
        }
    }

    // MARK: - Mutations

    func removeEntry(for email: Email) {
        entries.removeAll { $0.id == email.id }
    }

    func removeAll() {
        entries.removeAll()
        processedIDs.removeAll()
    }
}
