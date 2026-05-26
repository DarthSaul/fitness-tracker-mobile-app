import Foundation

nonisolated enum APIError: Error, LocalizedError, Equatable {
    case unauthorized
    /// Non-2xx HTTP response. `message` is the server-supplied human-readable
    /// reason (h3 `statusMessage` / `message`) when one could be decoded from
    /// the body — otherwise nil and `errorDescription` falls back to a generic
    /// status-code string. The raw body stays attached for diagnostic logging.
    case httpError(statusCode: Int, message: String?, data: Data)
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
        case .httpError(let code, let message, _):
            if let message, !message.isEmpty { return message }
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
        case (.httpError(let a, _, _), .httpError(let b, _, _)): return a == b
        case (.missingHandler(let a), .missingHandler(let b)): return a == b
        default: return false
        }
    }

    // MARK: - Server message decoding
    /// h3's `createError` serializes 4xx/5xx bodies as JSON with `statusMessage`
    /// and `message` fields. Pull either out (prefer `statusMessage`) so the UI
    /// can show "Session already completed" instead of "Server error (HTTP 409)".
    /// Returns nil on any decode failure or non-string fields — the caller falls
    /// back to the generic code-only message.
    static func decodeServerMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data)
        let raw = envelope?.statusMessage ?? envelope?.message
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private struct ServerErrorEnvelope: Decodable {
        let statusMessage: String?
        let message: String?
    }
}
