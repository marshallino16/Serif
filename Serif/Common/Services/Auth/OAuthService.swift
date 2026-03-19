import Foundation
import AppAuth
#if os(macOS)
import AppKit
#elseif os(iOS)
import AuthenticationServices
import CryptoKit
#endif

/// Handles Google OAuth 2.0 using AppAuth (loopback HTTP redirect flow).
/// Compatible with "Desktop app" credentials (redirect_uri = http://localhost).
@MainActor
final class OAuthService: NSObject {
    static let shared = OAuthService()
    private override init() {}

    /// Keeps the session alive for the duration of the OAuth flow.
    private var currentAuthorizationFlow: (any OIDExternalUserAgentSession)?
    #if os(macOS)
    /// Keeps the redirect HTTP handler alive for the duration of the OAuth flow.
    private var redirectHandler: OIDRedirectHTTPHandler?
    #endif

    // MARK: - Public API

    #if os(macOS)
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
    #else
    /// Runs the full OAuth flow on iOS using ASWebAuthenticationSession with PKCE.
    func authorize() async throws -> AuthToken {
        // 1. Generate PKCE code verifier and challenge
        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.sha256Base64URL(codeVerifier)

        // 2. Build the Google OAuth authorization URL
        let scopeString = GoogleCredentialsiOS.scopes.joined(separator: " ")
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id",             value: GoogleCredentialsiOS.clientID),
            URLQueryItem(name: "redirect_uri",          value: GoogleCredentialsiOS.redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: scopeString),
            URLQueryItem(name: "access_type",           value: "offline"),
            URLQueryItem(name: "prompt",                value: "consent"),
            URLQueryItem(name: "code_challenge",        value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else { throw OAuthError.invalidURL }

        // Extract the URL scheme from the redirect URI (everything before ":")
        let callbackScheme = GoogleCredentialsiOS.redirectURI.components(separatedBy: ":").first ?? ""

        // 3. Present ASWebAuthenticationSession and await the callback
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: OAuthError.noAuthCode)
                    return
                }
                continuation.resume(returning: url)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            session.start()
        }

        // 4. Extract the authorization code from the callback URL
        guard
            let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw OAuthError.noAuthCode
        }

        // 5. Exchange the authorization code for tokens (PKCE — no client_secret)
        let tokenParams: [String: String] = [
            "client_id":     GoogleCredentialsiOS.clientID,
            "code":          code,
            "redirect_uri":  GoogleCredentialsiOS.redirectURI,
            "grant_type":    "authorization_code",
            "code_verifier": codeVerifier
        ]

        let response: TokenResponse = try await postForm(to: "https://oauth2.googleapis.com/token", params: tokenParams)

        // 6. Return AuthToken
        return AuthToken(
            accessToken:  response.accessToken,
            refreshToken: response.refreshToken,
            expiresIn:    response.expiresIn,
            tokenType:    response.tokenType,
            scope:        response.scope ?? scopeString
        )
    }

    // MARK: - PKCE Helpers

    /// Generates a cryptographically random code verifier (43–128 URL-safe characters).
    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Returns the Base64-URL-encoded SHA-256 hash of the given verifier string.
    private static func sha256Base64URL(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    #endif

    /// Uses the stored refresh token to obtain a new access token.
    func refreshToken(_ token: AuthToken) async throws -> AuthToken {
        guard let refreshToken = token.refreshToken else { throw OAuthError.noRefreshToken }

        #if os(macOS)
        let params: [String: String] = [
            "client_id":     GoogleCredentials.clientID,
            "client_secret": GoogleCredentials.clientSecret,
            "refresh_token": refreshToken,
            "grant_type":    "refresh_token"
        ]
        #else
        let params: [String: String] = [
            "client_id":     GoogleCredentialsiOS.clientID,
            "refresh_token": refreshToken,
            "grant_type":    "refresh_token"
        ]
        #endif
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

// MARK: - ASWebAuthenticationPresentationContextProviding (iOS)

#if os(iOS)
extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync { self.presentationAnchor(for: session) }
        }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif

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
