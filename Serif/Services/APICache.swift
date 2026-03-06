import Foundation
import Combine

// MARK: - API Log Entry

struct APILogEntry: Identifiable {
    let id              = UUID()
    let date            = Date()
    let method          : String
    let path            : String
    let statusCode      : Int?
    let errorMessage    : String?
    let requestHeaders  : [String: String]
    let requestBody     : String?
    let responseHeaders : [String: String]
    let responseBody    : String
    let responseSize    : Int
    let durationMs      : Int
    let fromCache       : Bool
    let bodyTruncated   : Bool

    private static let maxBodyBytes = 200_000  // 200 KB

    /// Build an entry, truncating response body if needed.
    init(method: String, path: String, statusCode: Int?, errorMessage: String?,
         requestHeaders: [String: String] = [:], requestBody: String? = nil,
         responseHeaders: [String: String] = [:],
         responseBodyData: Data, responseSize: Int, durationMs: Int, fromCache: Bool) {
        self.method          = method
        self.path            = path
        self.statusCode      = statusCode
        self.errorMessage    = errorMessage
        self.requestHeaders  = requestHeaders
        self.requestBody     = requestBody
        self.responseHeaders = responseHeaders
        self.responseSize    = responseSize
        self.durationMs      = durationMs
        self.fromCache       = fromCache

        let limit = APILogEntry.maxBodyBytes
        if responseBodyData.count > limit {
            self.responseBody    = (String(data: responseBodyData.prefix(limit), encoding: .utf8) ?? "") + "\n…[truncated]"
            self.bodyTruncated   = true
        } else {
            self.responseBody    = String(data: responseBodyData, encoding: .utf8) ?? ""
            self.bodyTruncated   = false
        }
    }

    var shortPath: String {
        String(path.split(separator: "?").first ?? Substring(path))
    }

    enum StatusLevel { case success, cached, warning, error }

    var statusLevel: StatusLevel {
        guard let code = statusCode else { return .error }
        switch code {
        case 200...299: return fromCache ? .cached : .success
        case 429:       return .warning
        default:        return .error
        }
    }

    var statusLabel: String {
        if fromCache      { return "CACHE" }
        if let code = statusCode { return "\(code)" }
        return "ERR"
    }
}

// MARK: - API Logger

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

// MARK: - API Cache

/// Debug-only disk cache for Gmail API responses.
/// Disabled by default — enable via the Debug menu toggle.
final class APICache {
    static let shared = APICache()

    /// Toggle caching on/off without clearing stored data.
    var isEnabled = false

    private let cacheDir: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent("com.serif.app/api-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func get(path: String, accountID: String) -> Data? {
        guard isEnabled else { return nil }
        return try? Data(contentsOf: fileURL(path, accountID))
    }

    func set(_ data: Data, path: String, accountID: String) {
        guard isEnabled else { return }
        try? data.write(to: fileURL(path, accountID))
    }

    func clear() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil
        ) else { return }
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    var cachedResponseCount: Int {
        (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil))?.count ?? 0
    }

    private func fileURL(_ path: String, _ accountID: String) -> URL {
        let key = "\(accountID)|\(path)"
            .data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return cacheDir.appendingPathComponent(String(key.prefix(200)) + ".json")
    }
}