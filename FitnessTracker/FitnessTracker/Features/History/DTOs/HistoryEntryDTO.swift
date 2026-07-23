import Foundation

/// GET /api/history returns `{ sessions: [...] }` — the user's completed
/// sessions across program workouts AND standalone workouts, one list, newest
/// first. Rows are discriminated by `type`; rows with an unrecognized type
/// (future server additions) are dropped instead of failing the whole page.
nonisolated struct HistoryResponseDTO: Codable, Sendable, Equatable {
    let sessions: [HistoryEntryDTO]

    init(sessions: [HistoryEntryDTO]) {
        self.sessions = sessions
    }

    private enum CodingKeys: String, CodingKey {
        case sessions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tolerant = try container.decode([TolerantHistoryEntry].self, forKey: .sessions)
        self.sessions = tolerant.compactMap(\.entry)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessions, forKey: .sessions)
    }
}

/// One unified-history row. The payloads reuse the per-type row DTOs — the
/// server shapes are identical to the old per-type history rows apart from
/// the added `type` discriminator.
nonisolated enum HistoryEntryDTO: Codable, Sendable, Equatable, Identifiable {
    case program(HistorySessionDTO)
    case standalone(StandaloneSessionListItemDTO)

    static let programType = "PROGRAM"
    static let standaloneType = "STANDALONE"

    enum TypeCodingKeys: String, CodingKey {
        case type
    }

    /// Strict when decoded directly — an unknown type throws. Page-level
    /// tolerance lives in `HistoryResponseDTO` via `TolerantHistoryEntry`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeCodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case Self.programType:
            self = .program(try HistorySessionDTO(from: decoder))
        case Self.standaloneType:
            self = .standalone(try StandaloneSessionListItemDTO(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown history entry type '\(type)'"
            )
        }
    }

    /// Flattens the payload's keys alongside `type` in one object, matching
    /// the wire shape (used by tests stubbing the unified endpoint).
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeCodingKeys.self)
        switch self {
        case .program(let session):
            try container.encode(Self.programType, forKey: .type)
            try session.encode(to: encoder)
        case .standalone(let session):
            try container.encode(Self.standaloneType, forKey: .type)
            try session.encode(to: encoder)
        }
    }

    // MARK: - Shared accessors (pagination cursor + row chrome)

    var id: String {
        switch self {
        case .program(let session): return session.id
        case .standalone(let session): return session.id
        }
    }

    var startedAt: Date {
        switch self {
        case .program(let session): return session.startedAt
        case .standalone(let session): return session.startedAt
        }
    }

    var completedAt: Date? {
        switch self {
        case .program(let session): return session.completedAt
        case .standalone(let session): return session.completedAt
        }
    }

    var completedSets: Int {
        switch self {
        case .program(let session): return session.count.completedSets
        case .standalone(let session): return session.count.completedSets
        }
    }
}

/// Decode-only wrapper that maps rows with an unrecognized `type` to nil so
/// `compactMap` can drop them — one unknown future row type shouldn't fail
/// the whole history page.
private nonisolated struct TolerantHistoryEntry: Decodable {
    let entry: HistoryEntryDTO?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: HistoryEntryDTO.TypeCodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case HistoryEntryDTO.programType:
            entry = .program(try HistorySessionDTO(from: decoder))
        case HistoryEntryDTO.standaloneType:
            entry = .standalone(try StandaloneSessionListItemDTO(from: decoder))
        default:
            entry = nil
        }
    }
}
