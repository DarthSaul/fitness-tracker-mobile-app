import Foundation

enum JSONCoding {
    // MARK: - Shared Instances
    nonisolated static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // The server sends ISO 8601 with milliseconds (`2026-10-02T12:00:00.000Z`,
        // what `JSON.stringify` emits for a JS Date). The built-in `.iso8601`
        // strategy doesn't reliably parse fractional seconds across OS versions,
        // so parse explicitly — with milliseconds first, then without.
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseISO8601(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO 8601 date, got '\(raw)'"
                )
            }
            return date
        }
        return d
    }()

    nonisolated static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - ISO 8601

    /// Parses an ISO 8601 timestamp with or without fractional seconds.
    nonisolated static func parseISO8601(_ raw: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(raw)
    }
}
