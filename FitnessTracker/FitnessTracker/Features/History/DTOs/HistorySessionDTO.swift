import Foundation

/// GET /api/workouts/history returns sessions wrapped under "sessions".
/// Each entry is a completed WorkoutSession enriched with `_count.completedSets`
/// and the originating program's name.
nonisolated struct WorkoutHistoryResponseDTO: Codable, Sendable, Equatable {
    let sessions: [HistorySessionDTO]
}

nonisolated struct HistorySessionDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let userId: String
    let userProgramId: String
    let programName: String
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
        case id, userId, userProgramId, programName, weekNumber, dayNumber, status,
             startedAt, completedAt, notes
        case count = "_count"
    }
}
