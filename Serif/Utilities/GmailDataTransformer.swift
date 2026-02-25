import Foundation
import CryptoKit

/// Pure-data utilities for transforming Gmail API responses into app models.
/// All methods are static and have no side effects on app state.
enum GmailDataTransformer {

    // MARK: - Contact Parsing

    static func parseContact(_ raw: String) -> Contact {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Contact(name: "Unknown", email: "") }
        if let ltIdx = trimmed.lastIndex(of: "<"),
           let gtIdx = trimmed.lastIndex(of: ">"),
           ltIdx < gtIdx {
            let name  = String(trimmed[..<ltIdx])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let email = String(trimmed[trimmed.index(after: ltIdx)..<gtIdx]).trimmingCharacters(in: .whitespaces)
            return Contact(name: name.isEmpty ? email : name, email: email,
                           avatarColor: avatarColor(for: email), avatarURL: resolveAvatarURL(for: email))
        }
        return Contact(name: trimmed, email: trimmed,
                       avatarColor: avatarColor(for: trimmed), avatarURL: resolveAvatarURL(for: trimmed))
    }

    static func parseContacts(_ raw: String) -> [Contact] {
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { parseContact($0) }
    }

    // MARK: - Attachment

    static func makeAttachment(from part: GmailMessagePart) -> Attachment {
        let name = part.filename ?? "attachment"
        let ext  = String(name.split(separator: ".").last ?? "")
        let size = part.body.map { sizeString($0.size) } ?? ""
        return Attachment(name: name, fileType: .from(fileExtension: ext), size: size)
    }

    // MARK: - Folder

    static func folderFor(labelIDs: [String]) -> Folder {
        if labelIDs.contains("SENT")  { return .sent }
        if labelIDs.contains("DRAFT") { return .drafts }
        if labelIDs.contains("SPAM")  { return .spam }
        if labelIDs.contains("TRASH") { return .trash }
        return .inbox
    }

    // MARK: - UUID

    /// Generates a stable UUID from a Gmail message ID string.
    static func deterministicUUID(from gmailID: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in gmailID.utf8.prefix(16).enumerated() { bytes[i] = b }
        return UUID(uuid: (
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - Avatar

    static func avatarColor(for email: String) -> String {
        avatarColors[Int(stableHash(email) % UInt64(avatarColors.count))]
    }

    /// Returns the best available avatar URL for an email address:
    /// 1. Google People API (contacts with uploaded photos)
    /// 2. Signed-in account profile picture
    /// 3. Gravatar (SHA-256, d=404 so AvatarCache handles misses gracefully)
    static func resolveAvatarURL(for email: String) -> String {
        if let url = ContactPhotoCache.shared.get(email) { return url }
        if let url = AccountStore.shared.accounts.first(where: { $0.email == email })?.profilePictureURL?.absoluteString { return url }
        return gravatarURL(for: email)
    }

    // MARK: - Private helpers

    private static let avatarColors = [
        "#6C5CE7", "#00B894", "#E17055", "#0984E3",
        "#FDCB6E", "#E84393", "#00CEC9", "#A29BFE"
    ]

    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return hash
    }

    private static func gravatarURL(for email: String) -> String {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespaces)
        let hash = SHA256.hash(data: Data(normalized.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return "https://gravatar.com/avatar/\(hex)?s=80&d=404"
    }

    private static func sizeString(_ bytes: Int) -> String {
        if bytes < 1_024       { return "\(bytes) B" }
        if bytes < 1_048_576   { return String(format: "%.0f KB", Double(bytes) / 1_024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
