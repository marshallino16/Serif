import SwiftUI
import AppKit

// MARK: - AvatarCache

/// Disk-backed image cache with a 90-day TTL.
/// An empty on-disk file = "no image" (negative cache) to avoid re-fetching 404s.
final class AvatarCache {
    static let shared = AvatarCache()
    private init() {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private let ttl: TimeInterval = 90 * 24 * 60 * 60 // 90 days

    private let cacheDir: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.serif.avatars")

    func image(for urlString: String) async -> NSImage? {
        let fileURL = cacheDir.appendingPathComponent(cacheKey(for: urlString))

        // Serve from disk if still fresh
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < ttl {
            // Empty file = cached negative (404 / no image)
            guard let size = attrs[.size] as? Int, size > 0 else { return nil }
            // NSImage(contentsOfFile:) supports SVG + bitmaps; better than NSImage(data:) for SVG
            return NSImage(contentsOfFile: fileURL.path)
        }

        // Fetch from network
        guard let url = URL(string: urlString),
              let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200, !data.isEmpty else {
            try? Data().write(to: fileURL) // cache negative
            return nil
        }

        try? data.write(to: fileURL)
        return NSImage(contentsOfFile: fileURL.path)
    }

    private func cacheKey(for urlString: String) -> String {
        var hash: UInt64 = 5381
        for byte in urlString.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return "\(hash)"
    }
}

// MARK: - BIMIService

/// Resolves BIMI logo URLs for organizational sender domains via DNS-over-HTTPS (Cloudflare).
/// Personal/freemail domains are skipped immediately.
final class BIMIService {
    static let shared = BIMIService()
    private init() {}

    /// Domains that never have BIMI records — skip DNS lookup entirely.
    private static let personalDomains: Set<String> = [
        "gmail.com", "googlemail.com",
        "yahoo.com", "yahoo.fr", "yahoo.co.uk", "yahoo.co.jp", "yahoo.es", "yahoo.de",
        "hotmail.com", "hotmail.fr", "hotmail.co.uk", "hotmail.it",
        "outlook.com", "outlook.fr", "live.com", "live.fr",
        "icloud.com", "me.com", "mac.com",
        "protonmail.com", "proton.me", "pm.me",
        "aol.com", "wanadoo.fr", "orange.fr", "sfr.fr", "free.fr",
        "laposte.net", "bbox.fr", "numericable.fr"
    ]

    // in-memory: domain → logo URL or nil (nil means "no BIMI found")
    private var cache: [String: String?] = [:]
    private let lock = NSLock()

    func logoURL(for domain: String) async -> String? {
        let domain = domain.lowercased()
        guard !Self.personalDomains.contains(domain) else { return nil }

        if let cached = lock.withLock({ cache[domain] }) { return cached }

        let result = await resolveBIMI(for: domain)
        lock.withLock { cache[domain] = result }
        return result
    }

    private func resolveBIMI(for domain: String) async -> String? {
        let name = "default._bimi.\(domain)"
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://cloudflare-dns.com/dns-query?name=\(encoded)&type=TXT")
        else { return nil }

        var req = URLRequest(url: url)
        req.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 5

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let doh = try? JSONDecoder().decode(DoHResponse.self, from: data),
              doh.status == 0
        else { return nil }

        for answer in doh.answer ?? [] {
            guard answer.type == 16 else { continue } // TXT = 16
            // DNS TXT data may be quoted and split — normalize it
            let raw = answer.data
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "  ", with: " ")
            guard raw.contains("v=BIMI1") else { continue }
            for part in raw.split(separator: ";") {
                let kv = part.trimmingCharacters(in: .whitespaces)
                if kv.lowercased().hasPrefix("l=") {
                    let logoURL = String(kv.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if !logoURL.isEmpty { return logoURL }
                }
            }
        }
        return nil
    }
}

private struct DoHResponse: Decodable {
    let status: Int
    let answer: [DoHAnswer]?
    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case answer = "Answer"
    }
}

private struct DoHAnswer: Decodable {
    let type: Int
    let data: String
}

// MARK: - AvatarView

struct AvatarView: View {
    let initials: String
    let color: String
    var size: CGFloat = 36
    var avatarURL: String? = nil
    var senderDomain: String? = nil

    @State private var image: NSImage? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(hex: color))
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .task(id: avatarURL) {
            image = nil

            // 1. Try primary URL (People API photo / Gravatar)
            if let url = avatarURL, let img = await AvatarCache.shared.image(for: url) {
                image = img
                return
            }

            // 2. Fallback: BIMI logo for org/brand domains
            if let domain = senderDomain,
               let bimiURL = await BIMIService.shared.logoURL(for: domain),
               let img = await AvatarCache.shared.image(for: bimiURL) {
                image = img
            }
        }
    }
}
