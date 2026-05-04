import Foundation

nonisolated struct AnalyticsExerciseDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let sessionCount: Int
    let lastCompletedAt: Date
}

/// GET /api/analytics/exercises/[exerciseId] returns `{ exercise, history }`.
nonisolated struct AnalyticsExerciseHistoryDTO: Codable, Sendable, Equatable {
    let exercise: ExerciseRef
    let history: [SessionEntry]

    nonisolated struct ExerciseRef: Codable, Sendable, Equatable {
        let id: String
        let name: String
    }

    nonisolated struct SessionEntry: Codable, Sendable, Equatable, Identifiable {
        let sessionId: String
        let completedAt: Date
        let weekNumber: Int
        let dayNumber: Int
        let sets: [SessionSet]
        let bestE1rm: Double?
        let totalVolume: Double?

        var id: String { sessionId }
    }

    nonisolated struct SessionSet: Codable, Sendable, Equatable {
        let reps: Int?
        let weight: Double?
        let e1rm: Double?
    }
}
