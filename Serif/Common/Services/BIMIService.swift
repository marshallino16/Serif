import Foundation

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
