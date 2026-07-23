import Foundation

/// One completed program-workout session enriched with `_count.completedSets`
/// and the originating program's name. Appears as the `"type": "PROGRAM"`
/// payload of GET /api/history rows (see HistoryEntryDTO).
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
