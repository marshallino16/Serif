import AppKit
import PDFKit

/// In-memory + disk cache of attachment thumbnails, loaded on-demand with concurrency throttling.
@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()

    /// Cached thumbnails keyed by attachment ID.
    @Published private(set) var thumbnails: [String: NSImage] = [:]

    /// IDs currently being fetched (to avoid duplicate requests).
    private var loading: Set<String> = []

    /// Pending thumbnail requests queued when at capacity.
    private var pendingQueue: [(id: String, attachment: IndexedAttachment, accountID: String)] = []

    /// Number of active concurrent fetches.
    private var activeFetches = 0
    private let maxConcurrentFetches = 4

    /// Tracks in-flight fetch tasks so they can be cancelled on clearAll().
    private var fetchTasks: [String: Task<Void, Never>] = [:]

    private let maxSize = CGSize(width: 300, height: 200)

    /// Directory for disk-cached thumbnails.
    private let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("com.serif.thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func clearAll() {
        fetchTasks.values.forEach { $0.cancel() }
        fetchTasks.removeAll()
        thumbnails.removeAll()
        loading.removeAll()
        pendingQueue.removeAll()
        activeFetches = 0
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func thumbnail(for id: String) -> NSImage? {
        thumbnails[id]
    }

    /// Cancel a pending thumbnail load if the card scrolled offscreen before the fetch started.
    func cancelIfNeeded(id: String) {
        pendingQueue.removeAll { $0.id == id }
    }

    /// Request a thumbnail for an attachment. Loads from disk cache first, then network.
    func loadIfNeeded(attachment: IndexedAttachment, accountID: String) {
        let id = attachment.id
        guard thumbnails[id] == nil, !loading.contains(id) else { return }

        let fileType = Attachment.FileType(rawValue: attachment.fileType) ?? .document
        guard fileType == .image || fileType == .pdf else { return }

        // Try disk cache first
        if let diskImage = loadFromDisk(id: id) {
            thumbnails[id] = diskImage
            return
        }

        loading.insert(id)

        if activeFetches < maxConcurrentFetches {
            startFetch(id: id, attachment: attachment, accountID: accountID)
        } else {
            pendingQueue.append((id: id, attachment: attachment, accountID: accountID))
        }
    }

    // MARK: - Fetch

    private func startFetch(id: String, attachment: IndexedAttachment, accountID: String) {
        activeFetches += 1
        let msgId = attachment.messageId
        let attId = attachment.attachmentId
        let fileType = Attachment.FileType(rawValue: attachment.fileType) ?? .document

        let task = Task {
            defer {
                fetchTasks.removeValue(forKey: id)
                loading.remove(id)
                activeFetches = max(0, activeFetches - 1)
                dequeueNext()
            }
            do {
                let data = try await GmailMessageService.shared.getAttachment(
                    messageID: msgId,
                    attachmentID: attId,
                    accountID: accountID
                )
                guard !Task.isCancelled else { return }
                let thumb: NSImage? = switch fileType {
                case .image: Self.imageThumb(from: data, maxSize: maxSize)
                case .pdf:   Self.pdfThumb(from: data, maxSize: maxSize)
                default:     nil
                }
                if let thumb {
                    thumbnails[id] = thumb
                    saveToDisk(image: thumb, id: id)
                }
            } catch {
                // Silently skip — will show icon fallback
            }
        }
        fetchTasks[id] = task
    }

    private func dequeueNext() {
        guard activeFetches < maxConcurrentFetches, !pendingQueue.isEmpty else { return }
        let next = pendingQueue.removeFirst()
        // Skip if cancelled (removed from loading) or already cached
        guard loading.contains(next.id), thumbnails[next.id] == nil else {
            loading.remove(next.id)
            dequeueNext()
            return
        }
        startFetch(id: next.id, attachment: next.attachment, accountID: next.accountID)
    }

    // MARK: - Disk Cache

    private func cacheFileURL(for id: String) -> URL {
        let safeName = id.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent(safeName + ".jpg")
    }

    private func loadFromDisk(id: String) -> NSImage? {
        let url = cacheFileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private nonisolated func saveToDisk(image: NSImage, id: String) {
        let safeName = id.replacingOccurrences(of: "/", with: "_")
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.serif.thumbnails", isDirectory: true)
        let url = cacheDir.appendingPathComponent(safeName + ".jpg")
        Task.detached(priority: .utility) {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
            else { return }
            do {
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                try jpeg.write(to: url)
            } catch {
                // Directory may have been removed by concurrent clearAll(); skip silently
            }
        }
    }

    // MARK: - Generators

    private static func imageThumb(from data: Data, maxSize: CGSize) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxSize.width / size.width, maxSize.height / size.height, 1.0)
        let thumbSize = CGSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }

    private static func pdfThumb(from data: Data, maxSize: CGSize) -> NSImage? {
        guard let doc = PDFDocument(data: data),
              let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(maxSize.width / bounds.width, maxSize.height / bounds.height, 1.0)
        let thumbSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let thumb = page.thumbnail(of: thumbSize, for: .mediaBox)
        return thumb
    }
}
