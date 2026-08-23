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
        /// `type` discriminator values. Kept as a plain string (not an enum) so
        /// servers that predate the field — or add future values — never fail
        /// the whole trend payload.
        static let programType = "PROGRAM"
        static let standaloneType = "STANDALONE"

        let sessionId: String
        let completedAt: Date
        /// "PROGRAM" | "STANDALONE"; nil from servers that predate the field.
        let type: String?
        /// nil for standalone-session entries — they have no program position.
        let weekNumber: Int?
        let dayNumber: Int?
        /// Standalone workout name/category; nil for program entries.
        let workoutLabel: String?
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
