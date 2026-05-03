import Foundation
import Observation
import OSLog

// MARK: - Protocol
protocol APIClientProtocol {
    func send<T: Decodable>(_ endpoint: APIEndpoint) async throws(APIError) -> T
    func send(_ endpoint: APIEndpoint) async throws(APIError)
}

// MARK: - Concrete Client
// @Observable so it can be injected via .environment(apiClient) in SwiftUI.
@Observable
final class APIClient: APIClientProtocol {
    private let session: URLSession
    private let tokenStore: TokenStore
    private let tokenRefresher: TokenRefresher

    init(session: URLSession = .shared, tokenStore: TokenStore, tokenRefresher: TokenRefresher) {
        self.session = session
        self.tokenStore = tokenStore
        self.tokenRefresher = tokenRefresher
    }

    // MARK: - Send with Response
    func send<T: Decodable>(_ endpoint: APIEndpoint) async throws(APIError) -> T {
        let data = try await execute(endpoint, retried: false)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch let err as DecodingError {
            Logger.networking.error("Decoding failure for \(endpoint.path): \(err)")
            throw .decoding(err)
        } catch {
            throw .unknown(error)
        }
    }

    // MARK: - Send without Response
    func send(_ endpoint: APIEndpoint) async throws(APIError) {
        _ = try await execute(endpoint, retried: false)
    }

    // MARK: - Core Execution
    private func execute(_ endpoint: APIEndpoint, retried: Bool) async throws(APIError) -> Data {
        let sentAccessToken = await tokenStore.getAccessToken()
        let request: URLRequest
        do {
            request = try endpoint.urlRequest(baseURL: APIConfig.baseURL, accessToken: sentAccessToken)
        } catch {
            throw .unknown(error)
        }

        Logger.networking.debug("\(endpoint.method.rawValue) \(endpoint.path)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            Logger.networking.error("Network error: \(urlError)")
            throw .network(urlError)
        } catch {
            throw .unknown(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw .unknown(URLError(.badServerResponse))
        }

        Logger.networking.debug("\(http.statusCode) \(endpoint.path)")

        // Only attempt refresh if the failed request actually carried an access token.
        // Otherwise the 401 came from an unauthenticated endpoint (sign-in, refresh) and
        // refreshing makes no sense — it would just mask the real error.
        if http.statusCode == 401 && !retried && sentAccessToken != nil {
            Logger.networking.info("401 on \(endpoint.path) — attempting token refresh.")
            try await tokenRefresher.refresh()
            return try await execute(endpoint, retried: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes, non-utf8>"
            Logger.networking.error("HTTP \(http.statusCode) on \(endpoint.path): \(body, privacy: .public)")
            throw .httpError(statusCode: http.statusCode, data: data)
        }

        return data
    }
}
