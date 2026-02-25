import Foundation

final class GmailProfileService {
    static let shared = GmailProfileService()
    private init() {}

    // MARK: - Gmail Profile

    func getProfile(accountID: String) async throws -> GmailProfile {
        try await GmailAPIClient.shared.request(
            path: "/users/me/profile",
            accountID: accountID
        )
    }

    // MARK: - Google User Info (name, avatar)

    /// Fetches display name and profile picture from Google's userinfo endpoint.
    func getUserInfo(accessToken: String) async throws -> GoogleUserInfo {
        let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(GoogleUserInfo.self, from: data)
    }

    // MARK: - Signature

    /// Returns the signature HTML for the default send-as address.
    func getSignature(accountID: String) async throws -> String? {
        let response: GmailSendAsListResponse = try await GmailAPIClient.shared.request(
            path: "/users/me/settings/sendAs",
            accountID: accountID
        )
        return response.sendAs.first(where: { $0.isDefault == true })?.signature
    }

    // MARK: - Google People API

    /// Pre-loads contact photos from Google People API into ContactPhotoCache.
    /// Silently ignores errors (e.g. missing scope — user needs to re-authorize).
    func loadContactPhotos(accountID: String) async {
        do {
            var pageToken: String? = nil
            repeat {
                var urlStr = "https://people.googleapis.com/v1/people/me/connections"
                    + "?personFields=emailAddresses,photos&pageSize=1000&sortOrder=LAST_MODIFIED_DESCENDING"
                if let pt = pageToken { urlStr += "&pageToken=\(pt)" }
                let response: PeopleConnectionsResponse = try await GmailAPIClient.shared.requestURL(urlStr, accountID: accountID)
                for person in response.connections ?? [] {
                    // Only use non-default (user-uploaded) photos
                    guard let photo = person.photos?.first(where: { $0.default != true }),
                          let photoURL = photo.url else { continue }
                    for addr in person.emailAddresses ?? [] {
                        guard let email = addr.value, !email.isEmpty else { continue }
                        ContactPhotoCache.shared.set(photoURL, for: email)
                    }
                }
                pageToken = response.nextPageToken
            } while pageToken != nil
        } catch {
            // silently ignore
        }
    }
}

// MARK: - Contact Photo Cache

/// In-memory cache of email → Google profile photo URL, populated from People API at login.
final class ContactPhotoCache {
    static let shared = ContactPhotoCache()
    private init() {}

    private var cache: [String: String] = [:]
    private let lock = NSLock()

    func set(_ url: String, for email: String) {
        lock.withLock { cache[email.lowercased()] = url }
    }

    func get(_ email: String) -> String? {
        lock.withLock { cache[email.lowercased()] }
    }
}

// MARK: - People API response models

private struct PeopleConnectionsResponse: Decodable {
    let connections: [PersonResource]?
    let nextPageToken: String?
}

private struct PersonResource: Decodable {
    let emailAddresses: [PersonEmail]?
    let photos: [PersonPhoto]?
}

private struct PersonEmail: Decodable {
    let value: String?
}

private struct PersonPhoto: Decodable {
    let url: String?
    let `default`: Bool?
}

// MARK: - Google User Info Model

struct GoogleUserInfo: Decodable {
    let id:        String
    let email:     String
    let name:      String?
    let givenName: String?
    let picture:   String?

    enum CodingKeys: String, CodingKey {
        case id, email, name, picture
        case givenName = "given_name"
    }
}
