import Foundation

/// Base HTTP client for all Gmail API requests.
/// Automatically refreshes expired tokens before each call.
final class GmailAPIClient {
    static let shared = GmailAPIClient()
    private init() {}

    private let baseURL = "https://gmail.googleapis.com/gmail/v1"

    // MARK: - Decoded requests

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        accountID: String
    ) async throws -> T {
        let data = try await rawRequest(path: path, method: method, body: body, contentType: contentType, accountID: accountID)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GmailAPIError.decodingError(error)
        }
    }

    /// Returns raw Data (e.g. for DELETE responses or binary payloads).
    func rawRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        accountID: String
    ) async throws -> Data {
        #if DEBUG
        if method == "GET", let cached = APICache.shared.get(path: path, accountID: accountID) {
            await APILogger.shared.log(APILogEntry(
                method: method, path: path, statusCode: 200, errorMessage: nil,
                responseBody: String(data: cached, encoding: .utf8).map { String($0.prefix(1000)) } ?? "",
                responseSize: cached.count, durationMs: 0, fromCache: true
            ))
            return cached
        }
        #endif

        let token = try await validToken(for: accountID)

        #if DEBUG
        let t0 = Date()
        do {
            let (data, code) = try await perform(path: path, method: method, body: body, contentType: contentType, accessToken: token.accessToken)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            await APILogger.shared.log(APILogEntry(
                method: method, path: path, statusCode: code, errorMessage: nil,
                responseBody: String(data: data, encoding: .utf8).map { String($0.prefix(1000)) } ?? "",
                responseSize: data.count, durationMs: ms, fromCache: false
            ))
            if method == "GET" { APICache.shared.set(data, path: path, accountID: accountID) }
            return data
        } catch GmailAPIError.httpError(let code, let errData) {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            await APILogger.shared.log(APILogEntry(
                method: method, path: path, statusCode: code, errorMessage: "HTTP \(code)",
                responseBody: String(data: errData, encoding: .utf8).map { String($0.prefix(1000)) } ?? "",
                responseSize: errData.count, durationMs: ms, fromCache: false
            ))
            throw GmailAPIError.httpError(code, errData)
        } catch {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            await APILogger.shared.log(APILogEntry(
                method: method, path: path, statusCode: nil, errorMessage: error.localizedDescription,
                responseBody: "", responseSize: 0, durationMs: ms, fromCache: false
            ))
            throw error
        }
        #else
        let (data, _) = try await perform(path: path, method: method, body: body, contentType: contentType, accessToken: token.accessToken)
        return data
        #endif
    }

    // MARK: - Authenticated request to any Google API URL

    /// Makes an authenticated GET request to any Google API (not limited to the Gmail base URL).
    func requestURL<T: Decodable>(_ urlString: String, accountID: String) async throws -> T {
        let token = try await validToken(for: accountID)
        guard let url = URL(string: urlString) else { throw GmailAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GmailAPIError.invalidURL }
        guard (200...299).contains(http.statusCode) else { throw GmailAPIError.httpError(http.statusCode, data) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GmailAPIError.decodingError(error) }
    }

    // MARK: - Token refresh

    @MainActor
    private func validToken(for accountID: String) async throws -> AuthToken {
        guard var token = try TokenStore.shared.retrieve(for: accountID) else {
            throw GmailAPIError.unauthorized
        }
        if token.isExpired {
            token = try await OAuthService.shared.refreshToken(token)
            try TokenStore.shared.save(token, for: accountID)
        }
        return token
    }

    // MARK: - HTTP layer

    /// Returns (data, httpStatusCode).
    private func perform(
        path: String,
        method: String,
        body: Data?,
        contentType: String?,
        accessToken: String
    ) async throws -> (Data, Int) {
        guard let url = URL(string: baseURL + path) else { throw GmailAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GmailAPIError.invalidURL }

        switch http.statusCode {
        case 200...299: return (data, http.statusCode)
        case 401:       throw GmailAPIError.unauthorized
        default:        throw GmailAPIError.httpError(http.statusCode, data)
        }
    }
}

// MARK: - Errors

enum GmailAPIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case httpError(Int, Data)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid API URL"
        case .unauthorized:         return "Unauthorized — please sign in again"
        case .httpError(let c, _):  return "HTTP \(c)"
        case .decodingError(let e): return "Decode failed: \(e.localizedDescription)"
        }
    }
}
