import Foundation
@testable import FitnessTracker

// MARK: - Mock
final class MockAPIClient: APIClientProtocol {
    /// Handlers keyed by `"METHOD path"` (e.g. `"GET /api/feedback"`) so the
    /// same wire path can dispatch independently across HTTP methods —
    /// `getFeedback` (GET) and `createFeedback` (POST) both hit `/api/feedback`
    /// but need distinct stubs. Hit an unstubbed key and resolve() throws
    /// `APIError.missingHandler` — silent empty-Data success would mask
    /// missing test setup.
    var handlers: [String: (APIEndpoint) throws -> Data] = [:]

    func send<T: Decodable>(_ endpoint: APIEndpoint) async throws(APIError) -> T {
        let data = try resolve(endpoint)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch let err as DecodingError {
            throw .decoding(err)
        } catch {
            throw .unknown(error)
        }
    }

    func send(_ endpoint: APIEndpoint) async throws(APIError) {
        _ = try resolve(endpoint)
    }

    /// Records the most recent multipart call so tests can assert the parts
    /// that were sent (e.g. that an attached screenshot reached the wire).
    /// Resolves through the same key-based handler map as `send`.
    var lastMultipartParts: [MultipartPart]?
    func sendMultipart<T: Decodable>(_ endpoint: APIEndpoint, parts: [MultipartPart]) async throws(APIError) -> T {
        lastMultipartParts = parts
        let data = try resolve(endpoint)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch let err as DecodingError {
            throw .decoding(err)
        } catch {
            throw .unknown(error)
        }
    }

    // MARK: - Key helpers
    /// Build the handler key for an endpoint case. Used by both the typed
    /// `stub(...)` convenience and tests that index `handlers` directly.
    static func key(for endpoint: APIEndpoint) -> String {
        key(method: endpoint.method, path: endpoint.path)
    }

    static func key(method: HTTPMethod, path: String) -> String {
        "\(method.rawValue) \(path)"
    }

    // MARK: - Helpers
    private func resolve(_ endpoint: APIEndpoint) throws(APIError) -> Data {
        let key = Self.key(for: endpoint)
        guard let handler = handlers[key] else {
            throw APIError.missingHandler(path: key)
        }
        do {
            return try handler(endpoint)
        } catch let err as APIError {
            throw err
        } catch {
            throw .unknown(error)
        }
    }

    // MARK: - Convenience Setters
    func stub<T: Encodable>(_ endpoint: APIEndpoint, response: T) {
        handlers[Self.key(for: endpoint)] = { _ in try JSONCoding.encoder.encode(response) }
    }

    /// Stub a 401 for an endpoint by case — fewer typos, stays in sync with
    /// `APIEndpoint.path`/`method` automatically.
    func stubUnauthorized(for endpoint: APIEndpoint) {
        handlers[Self.key(for: endpoint)] = { _ in throw APIError.unauthorized }
    }

    /// Stub a 401 by method + path for cases where building the full endpoint
    /// case would require synthetic body fixtures (e.g. PATCH cases that carry
    /// a body in the associated value). Prefer `stubUnauthorized(for:)` when
    /// the endpoint case is easy to construct.
    func stubUnauthorized(method: HTTPMethod, path: String) {
        handlers[Self.key(method: method, path: path)] = { _ in throw APIError.unauthorized }
    }
}
