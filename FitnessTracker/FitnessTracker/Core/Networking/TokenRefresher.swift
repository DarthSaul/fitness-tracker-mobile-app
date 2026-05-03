import Foundation
import OSLog

// MARK: - Token Refresher
// Actor that serializes refresh calls. Multiple concurrent 401s share a single in-flight refresh Task.
actor TokenRefresher {
    private let keychain: KeychainService
    private let tokenStore: TokenStore
    private var refreshTask: Task<Void, any Error>?

    init(keychain: KeychainService, tokenStore: TokenStore) {
        self.keychain = keychain
        self.tokenStore = tokenStore
    }

    // MARK: - Refresh
    func refresh() async throws(APIError) {
        if let existing = refreshTask {
            do {
                try await existing.value
            } catch let err as APIError {
                throw err
            } catch {
                throw .unknown(error)
            }
            return
        }

        let task = Task<Void, any Error> { [keychain, tokenStore] in
            try await Self.performRefresh(keychain: keychain, tokenStore: tokenStore)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            try await task.value
        } catch let err as APIError {
            throw err
        } catch {
            throw .unknown(error)
        }
    }

    // MARK: - Private
    private static func performRefresh(keychain: KeychainService, tokenStore: TokenStore) async throws {
        let stored: String
        do {
            stored = try await keychain.load(.refreshToken)
        } catch KeychainError.itemNotFound {
            // Genuine "no session yet" — surface as unauthorized so the UI
            // routes to sign-in.
            Logger.auth.warning("No refresh token in Keychain — cannot refresh session.")
            throw APIError.unauthorized
        } catch {
            // Any other Keychain failure (read error, decoding, OSStatus) is
            // a transient/system issue, not an auth problem. Don't mask it.
            Logger.auth.error("Keychain load failed for refreshToken: \(error)")
            throw error
        }

        let body = RefreshTokenBody(refreshToken: stored)
        let bodyData = try JSONCoding.encoder.encode(body)

        var request = URLRequest(url: APIConfig.baseURL.appending(path: "/api/auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.unknown(URLError(.badServerResponse)) }

        if http.statusCode == 401 {
            try? await keychain.delete(.refreshToken)
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, data: data)
        }

        let tokens = try JSONCoding.decoder.decode(AuthTokensResponse.self, from: data)
        await tokenStore.set(access: tokens.accessToken)
        try await keychain.save(tokens.refreshToken, for: .refreshToken)
        Logger.auth.info("Token refresh succeeded.")
    }
}

// MARK: - Response Type (shared with AuthRepository)
nonisolated struct AuthTokensResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
}
