import Foundation

struct AuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let tokenType: String
    let scope: String

    /// Returns true if the token is expired or expires within 60s.
    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }

    init(accessToken: String, refreshToken: String?, expiresIn: Int, tokenType: String, scope: String) {
        self.accessToken  = accessToken
        self.refreshToken = refreshToken
        self.expiresAt    = Date().addingTimeInterval(TimeInterval(expiresIn))
        self.tokenType    = tokenType
        self.scope        = scope
    }
}
