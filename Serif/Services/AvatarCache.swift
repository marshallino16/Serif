import AppKit

/// Disk-backed image cache with a 90-day TTL.
/// An empty on-disk file = "no image" (negative cache) to avoid re-fetching 404s.
final class AvatarCache {
    static let shared = AvatarCache()
    private init() {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        memoryCache.countLimit = 200
    }

    private let ttl: TimeInterval = 90 * 24 * 60 * 60 // 90 days

    /// In-memory LRU cache to avoid repeated disk reads on scroll.
    private let memoryCache = NSCache<NSString, NSImage>()
    /// Tracks negative lookups in memory (URLs that returned 404 / no image).
    private let negativeCacheKeys = NSCache<NSString, NSNull>()

    private let cacheDir: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.serif.avatars")

    func image(for urlString: String) async -> NSImage? {
        let key = cacheKey(for: urlString) as NSString

        // 1. In-memory hit
        if let cached = memoryCache.object(forKey: key) { return cached }
        if negativeCacheKeys.object(forKey: key) != nil { return nil }

        let fileURL = cacheDir.appendingPathComponent(key as String)

        // 2. Serve from disk if still fresh
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < ttl {
            // Empty file = cached negative (404 / no image)
            guard let size = attrs[.size] as? Int, size > 0 else {
                negativeCacheKeys.setObject(NSNull(), forKey: key)
                return nil
            }
            if let img = NSImage(contentsOfFile: fileURL.path) {
                memoryCache.setObject(img, forKey: key)
                return img
            }
            return nil
        }

        // 3. Fetch from network
        guard let url = URL(string: urlString),
              let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200, !data.isEmpty else {
            try? Data().write(to: fileURL) // cache negative on disk
            negativeCacheKeys.setObject(NSNull(), forKey: key)
            return nil
        }

        try? data.write(to: fileURL)
        if let img = NSImage(contentsOfFile: fileURL.path) {
            memoryCache.setObject(img, forKey: key)
            return img
        }
        return nil
    }

    /// Remove all cached avatar images from disk.
    func clearAll() {
        memoryCache.removeAllObjects()
        negativeCacheKeys.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func cacheKey(for urlString: String) -> String {
        var hash: UInt64 = 5381
        for byte in urlString.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return "\(hash)"
    }
}
