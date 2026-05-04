import Foundation

/// GET /api/user-programs/active/sessions returns sessions wrapped under "sessions".
/// Each entry is a WorkoutSession with a `_count.completedSets` aggregate.
nonisolated struct ActiveProgramSessionsResponseDTO: Codable, Sendable, Equatable {
    let sessions: [ActiveProgramSessionDTO]
}

nonisolated struct ActiveProgramSessionDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let userId: String
    let userProgramId: String
    let weekNumber: Int
    let dayNumber: Int
    let status: SessionStatus
    let startedAt: Date
    let completedAt: Date?
    let notes: String?
    let count: Count

    nonisolated struct Count: Codable, Sendable, Equatable {
        let completedSets: Int
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, userProgramId, weekNumber, dayNumber, status,
             startedAt, completedAt, notes
        case count = "_count"
    }
}
