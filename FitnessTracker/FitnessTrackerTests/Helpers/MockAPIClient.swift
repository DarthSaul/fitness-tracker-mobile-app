import Foundation
@testable import FitnessTracker

// MARK: - Mock
final class MockAPIClient: APIClientProtocol {
    // One handler per endpoint path. Hit an unstubbed endpoint and resolve()
    // throws APIError.missingHandler — silent empty-Data success masks
    // missing test setup.
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

    // MARK: - Helpers
    private func resolve(_ endpoint: APIEndpoint) throws(APIError) -> Data {
        guard let handler = handlers[endpoint.path] else {
            throw APIError.missingHandler(path: endpoint.path)
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
        handlers[endpoint.path] = { _ in try JSONCoding.encoder.encode(response) }
    }

    func stubUnauthorized(for path: String) {
        handlers[path] = { _ in throw APIError.unauthorized }
    }

    /// Convenience overload so tests can stub by case rather than by string
    /// path — fewer typos, and stays in sync with `APIEndpoint.path` automatically.
    func stubUnauthorized(for endpoint: APIEndpoint) {
        stubUnauthorized(for: endpoint.path)
    }
}
