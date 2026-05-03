import Foundation
@testable import FitnessTracker

// MARK: - Mock
final class MockAPIClient: APIClientProtocol {
    // Store a handler per endpoint path; throwing nil means return empty Data
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
            return Data()
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
}
