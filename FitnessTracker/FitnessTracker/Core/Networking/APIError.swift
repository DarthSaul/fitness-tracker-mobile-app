import Foundation

nonisolated enum APIError: Error, LocalizedError, Equatable {
    case unauthorized
    case httpError(statusCode: Int, data: Data)
    case decoding(DecodingError)
    case network(URLError)
    case unknown(any Error)

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
        }
    }

    // MARK: - Equatable
    // Compares cases that carry comparable payload; payload-bearing variants only match
    // by status code or case identity. Used by the UI layer to detect .unauthorized.
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.httpError(let a, _), .httpError(let b, _)): return a == b
        default: return false
        }
    }
}
