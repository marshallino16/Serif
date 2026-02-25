import Foundation
import AppAuth

/// Handles Google OAuth 2.0 using AppAuth (loopback HTTP redirect flow).
/// Compatible with "Desktop app" credentials (redirect_uri = http://localhost).
@MainActor
final class OAuthService: NSObject {
    static let shared = OAuthService()
    private override init() {}

    /// Keeps the session alive for the duration of the OAuth flow.
    private var currentAuthorizationFlow: (any OIDExternalUserAgentSession)?
    /// Keeps the redirect HTTP handler alive for the duration of the OAuth flow.
    private var redirectHandler: OIDRedirectHTTPHandler?

    // MARK: - Public API

    /// Runs the full OAuth flow: opens system browser → loopback redirect → tokens.
    func authorize(presentingWindow: NSWindow?) async throws -> AuthToken {
        let config = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )

        // AppAuth starts a local HTTP server on a random port and returns its URL.
        // That URL becomes the redirect_uri for this sign-in session.
        let handler = OIDRedirectHTTPHandler(successURL: nil)
        self.redirectHandler = handler
        let redirectURI = handler.startHTTPListener(nil)

        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: GoogleCredentials.clientID,
            clientSecret: GoogleCredentials.clientSecret,
            scopes: GoogleCredentials.scopes,
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: ["access_type": "offline", "prompt": "consent"]
        )

        let window = presentingWindow
            ?? NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? NSWindow()

        return try await withCheckedThrowingContinuation { continuation in
            // authState(byPresenting:presenting:callback:) opens the system browser
            // via NSWorkspace and waits for the loopback redirect to complete.
            handler.currentAuthorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting: window
            ) { [weak self] authState, error in
                self?.redirectHandler = nil
                self?.currentAuthorizationFlow = nil

                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard
                    let tokenResponse = authState?.lastTokenResponse,
                    let accessToken   = tokenResponse.accessToken,
                    let refreshToken  = authState?.refreshToken
                else {
                    continuation.resume(throwing: OAuthError.noRefreshToken)
                    return
                }

                let expiresIn = Int(tokenResponse.accessTokenExpirationDate?.timeIntervalSinceNow ?? 3600)
                let token = AuthToken(
                    accessToken:  accessToken,
                    refreshToken: refreshToken,
                    expiresIn:    max(expiresIn, 1),
                    tokenType:    tokenResponse.tokenType ?? "Bearer",
                    scope:        tokenResponse.scope ?? ""
                )
                continuation.resume(returning: token)
            }
        }
    }

    /// Uses the stored refresh token to obtain a new access token.
    func refreshToken(_ token: AuthToken) async throws -> AuthToken {
        guard let refreshToken = token.refreshToken else { throw OAuthError.noRefreshToken }

        let params: [String: String] = [
            "client_id":     GoogleCredentials.clientID,
            "client_secret": GoogleCredentials.clientSecret,
            "refresh_token": refreshToken,
            "grant_type":    "refresh_token"
        ]
        let response: TokenResponse = try await postForm(to: "https://oauth2.googleapis.com/token", params: params)
        return AuthToken(
            accessToken:  response.accessToken,
            refreshToken: token.refreshToken,
            expiresIn:    response.expiresIn,
            tokenType:    response.tokenType,
            scope:        response.scope ?? token.scope
        )
    }

    // MARK: - Private

    private func postForm<T: Decodable>(to urlString: String, params: [String: String]) async throws -> T {
        guard let url = URL(string: urlString) else { throw OAuthError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Token Response (manual refresh only)

private struct TokenResponse: Decodable {
    let accessToken:  String
    let refreshToken: String?
    let expiresIn:    Int
    let tokenType:    String
    let scope:        String?

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
        case tokenType    = "token_type"
        case scope
    }
}

// MARK: - Errors

enum OAuthError: Error, LocalizedError {
    case invalidURL
    case noAuthCode
    case noRefreshToken
    case listenerFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:      return "Invalid OAuth URL"
        case .noAuthCode:      return "No authorization code received"
        case .noRefreshToken:  return "No refresh token received"
        case .listenerFailed:  return "Failed to start local HTTP redirect listener"
        }
    }
}
