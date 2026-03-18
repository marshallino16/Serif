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
/// Validated subscription IDs are persisted per account so they survive restarts.
@MainActor
final class SubscriptionsStore: ObservableObject {
    static let shared = SubscriptionsStore()

    @Published private(set) var entries:     [Email] = []
    @Published private(set) var isAnalyzing: Bool    = false

    var accountID: String = "" {
        didSet {
            guard accountID != oldValue else { return }
            entries.removeAll()
            processedIDs.removeAll()
            validatedIDs = loadValidatedIDs()
            // Already validated IDs count as processed (skip HEAD next time)
            processedIDs = validatedIDs
        }
    }

    private var processedIDs = Set<String>()   // per-session dedup
    private var validatedIDs = Set<String>()   // persisted validated subscription IDs
    private let urlCache     = URLValidityCache()
    private var pendingCount = 0               // tracks concurrent analysis tasks

    private init() {}

    // MARK: - Persistence

    private var defaultsKey: String { "subscriptionIDs.\(accountID)" }

    private func loadValidatedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    private func saveValidatedIDs() {
        UserDefaults.standard.set(Array(validatedIDs), forKey: defaultsKey)
    }

    // MARK: - Analyze

    /// Call this whenever new emails are available.  Already-processed messages
    /// are skipped.  Eligible emails are those with a valid unsubscribeURL.
    func analyze(_ emails: [Email]) {
        // Instantly surface known subscriptions from previous sessions (no HEAD needed)
        let knownSubscriptions = emails.filter { email in
            guard let id = email.gmailMessageID,
                  validatedIDs.contains(id),
                  !entries.contains(where: { $0.id == email.id })
            else { return false }
            return true
        }
        if !knownSubscriptions.isEmpty {
            entries.append(contentsOf: knownSubscriptions)
            entries.sort { $0.date > $1.date }
        }

        // Filter new candidates that need HEAD validation
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
            var newValidated = false
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
                    if let id = email.gmailMessageID {
                        validatedIDs.insert(id)
                        newValidated = true
                    }
                }
            }
            entries.sort { $0.date > $1.date }
            if newValidated { saveValidatedIDs() }

            pendingCount -= 1
            if pendingCount == 0 { isAnalyzing = false }
        }
    }

    // MARK: - Mutations

    func removeEntry(for email: Email) {
        entries.removeAll { $0.id == email.id }
        if let id = email.gmailMessageID {
            validatedIDs.remove(id)
            saveValidatedIDs()
        }
    }

    func removeAll() {
        entries.removeAll()
        processedIDs.removeAll()
        validatedIDs.removeAll()
        if !accountID.isEmpty { saveValidatedIDs() }
    }

    /// Wipes persisted data for a specific account (called on sign-out).
    func deleteAccount(_ accountID: String) {
        UserDefaults.standard.removeObject(forKey: "subscriptionIDs.\(accountID)")
        if self.accountID == accountID {
            entries.removeAll()
            processedIDs.removeAll()
            validatedIDs.removeAll()
        }
    }
}
