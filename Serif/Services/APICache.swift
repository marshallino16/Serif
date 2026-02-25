#if DEBUG
import Foundation
import SwiftUI

// MARK: - API Log

struct APILogEntry: Identifiable {
    let id          = UUID()
    let date        = Date()
    let method      : String
    let path        : String        // full path with query params
    let statusCode  : Int?          // nil = client/network error
    let errorMessage: String?
    let responseBody: String        // truncated to 1000 chars
    let responseSize: Int           // bytes
    let durationMs  : Int
    let fromCache   : Bool

    var shortPath: String {
        // Strip query string for display
        String(path.split(separator: "?").first ?? Substring(path))
    }

    var statusColor: Color {
        guard let code = statusCode else { return .red }
        switch code {
        case 200...299: return fromCache ? Color.gray : Color.green
        case 429:       return .orange
        case 400...499: return .red
        case 500...599: return .red
        default:        return .yellow
        }
    }

    var statusLabel: String {
        if fromCache { return "CACHE" }
        if let code = statusCode { return "\(code)" }
        return "ERR"
    }
}

@MainActor
final class APILogger: ObservableObject {
    static let shared = APILogger()
    private init() {}

    @Published private(set) var entries: [APILogEntry] = []
    private let maxEntries = 200

    func log(_ entry: APILogEntry) {
        if entries.count >= maxEntries { entries.removeFirst() }
        entries.append(entry)
    }

    func clear() { entries = [] }
}


/// Debug-only disk cache for Gmail API responses.
/// Caches GET responses so the app can be developed without hitting the API every run.
///
/// To disable: flip `isEnabled = false` below, or delete all cache via DebugMenuView.
/// To remove entirely: delete this file and the #if DEBUG blocks in GmailAPIClient.
final class APICache {
    static let shared = APICache()

    /// Toggle caching on/off without clearing stored data.
    var isEnabled = true

    private let cacheDir: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent("com.serif.app/api-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Read / Write

    func get(path: String, accountID: String) -> Data? {
        guard isEnabled else { return nil }
        return try? Data(contentsOf: fileURL(path, accountID))
    }

    func set(_ data: Data, path: String, accountID: String) {
        guard isEnabled else { return }
        try? data.write(to: fileURL(path, accountID))
    }

    // MARK: - Invalidation

    func clear() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil
        ) else { return }
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    var cachedResponseCount: Int {
        (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil))?.count ?? 0
    }

    // MARK: - Key

    private func fileURL(_ path: String, _ accountID: String) -> URL {
        let key = "\(accountID)|\(path)"
            .data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        // Truncate to avoid filesystem path-length limits
        let truncated = String(key.prefix(200))
        return cacheDir.appendingPathComponent(truncated + ".json")
    }
}
#endif
