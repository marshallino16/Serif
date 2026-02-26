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

    // MARK: - SendAs / Aliases

    /// Returns all SendAs aliases for the account.
    func listSendAs(accountID: String) async throws -> [GmailSendAs] {
        let response: GmailSendAsListResponse = try await GmailAPIClient.shared.request(
            path: "/users/me/settings/sendAs",
            accountID: accountID
        )
        return response.sendAs
    }

    /// Returns the signature HTML for the default send-as address.
    func getSignature(accountID: String) async throws -> String? {
        let aliases = try await listSendAs(accountID: accountID)
        return aliases.first(where: { $0.isDefault == true })?.signature
    }

    // MARK: - Google People API

    /// Loads contacts: uses local cache if available, otherwise fetches from network.
    func loadContactPhotos(accountID: String) async {
        let local = ContactStore.shared.contacts(for: accountID)
        if !local.isEmpty {
            print("[Serif] Using \(local.count) cached contacts for \(accountID)")
            // Still populate the photo cache from local contacts (in-memory only)
            return
        }
        await fetchAndStoreContacts(accountID: accountID)
    }

    /// Forces a network refresh of contacts, replacing the local cache.
    func refreshContacts(accountID: String) async {
        await fetchAndStoreContacts(accountID: accountID)
    }

    /// Fetches contacts from People API and persists them.
    private func fetchAndStoreContacts(accountID: String) async {
        var allContacts: [StoredContact] = []

        // 1. Fetch "My Contacts" via connections
        do {
            var pageToken: String? = nil
            repeat {
                var urlStr = "https://people.googleapis.com/v1/people/me/connections"
                    + "?personFields=names,emailAddresses,photos&pageSize=1000&sortOrder=LAST_MODIFIED_DESCENDING"
                if let pt = pageToken { urlStr += "&pageToken=\(pt)" }
                let response: PeopleConnectionsResponse = try await GmailAPIClient.shared.requestURL(urlStr, accountID: accountID)
                for person in response.connections ?? [] {
                    if let photo = person.photos?.first(where: { $0.default != true }),
                       let photoURL = photo.url {
                        for addr in person.emailAddresses ?? [] {
                            guard let email = addr.value, !email.isEmpty else { continue }
                            ContactPhotoCache.shared.set(photoURL, for: email)
                        }
                    }
                    let displayName = person.names?.first?.displayName ?? ""
                    for addr in person.emailAddresses ?? [] {
                        guard let email = addr.value, !email.isEmpty else { continue }
                        allContacts.append(StoredContact(name: displayName, email: email.lowercased()))
                    }
                }
                pageToken = response.nextPageToken
            } while pageToken != nil
            print("[Serif] Loaded \(allContacts.count) contacts from Connections")
        } catch {
            print("[Serif] Connections fetch error: \(error)")
        }

        // 2. Fetch "Other Contacts" (auto-created from email interactions)
        do {
            var pageToken: String? = nil
            repeat {
                var urlStr = "https://people.googleapis.com/v1/otherContacts"
                    + "?readMask=names,emailAddresses&pageSize=1000"
                if let pt = pageToken { urlStr += "&pageToken=\(pt)" }
                let response: OtherContactsResponse = try await GmailAPIClient.shared.requestURL(urlStr, accountID: accountID)
                let beforeCount = allContacts.count
                for person in response.otherContacts ?? [] {
                    let displayName = person.names?.first?.displayName ?? ""
                    for addr in person.emailAddresses ?? [] {
                        guard let email = addr.value, !email.isEmpty else { continue }
                        allContacts.append(StoredContact(name: displayName, email: email.lowercased()))
                    }
                }
                print("[Serif] Loaded \(allContacts.count - beforeCount) from Other Contacts page")
                pageToken = response.nextPageToken
            } while pageToken != nil
        } catch {
            print("[Serif] Other Contacts fetch error: \(error)")
        }

        // Deduplicate by email and persist
        var seen = Set<String>()
        let unique = allContacts.filter { seen.insert($0.email).inserted }
        ContactStore.shared.setContacts(unique, for: accountID)
        print("[Serif] Total unique contacts stored: \(unique.count)")
    }
}

// MARK: - Stored Contact

struct StoredContact: Codable, Identifiable, Hashable {
    var id: String { email }
    let name: String
    let email: String
}

// MARK: - Contact Store (UserDefaults persistence)

final class ContactStore {
    static let shared = ContactStore()
    private init() {}

    func contacts(for accountID: String) -> [StoredContact] {
        let key = "com.serif.contacts.\(accountID)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([StoredContact].self, from: data)
        else { return [] }
        return decoded
    }

    func setContacts(_ contacts: [StoredContact], for accountID: String) {
        let key = "com.serif.contacts.\(accountID)"
        let data = try? JSONEncoder().encode(contacts)
        UserDefaults.standard.set(data, forKey: key)
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

private struct OtherContactsResponse: Decodable {
    let otherContacts: [PersonResource]?
    let nextPageToken: String?
}

private struct PersonResource: Decodable {
    let emailAddresses: [PersonEmail]?
    let photos: [PersonPhoto]?
    let names: [PersonName]?
}

private struct PersonEmail: Decodable {
    let value: String?
}

private struct PersonPhoto: Decodable {
    let url: String?
    let `default`: Bool?
}

private struct PersonName: Decodable {
    let displayName: String?
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
