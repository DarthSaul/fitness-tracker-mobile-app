import Foundation

nonisolated enum APIError: Error, LocalizedError, Equatable {
    case unauthorized
    case httpError(statusCode: Int, data: Data)
    case decoding(DecodingError)
    case network(URLError)
    case unknown(any Error)
    /// Test-only signal from MockAPIClient when an endpoint is hit without
    /// having been stubbed. Surfaces immediately rather than the mock
    /// returning empty Data and pretending success.
    case missingHandler(path: String)

    // MARK: - LocalizedError
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .httpError(let code, _):
            return "Server error (HTTP \(code))."
        case .decoding:
            return "Unexpected response from the server."
        case .network(let err):
            return err.localizedDescription
        case .unknown(let err):
            return err.localizedDescription
        case .missingHandler(let path):
            return "MockAPIClient: no stub registered for \(path)."
        }
    }

    // MARK: - Equatable
    // Compares cases that carry comparable payload; payload-bearing variants only match
    // by status code or case identity. Used by the UI layer to detect .unauthorized.
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.httpError(let a, _), .httpError(let b, _)): return a == b
        case (.missingHandler(let a), .missingHandler(let b)): return a == b
        default: return false
        }
    }
}
