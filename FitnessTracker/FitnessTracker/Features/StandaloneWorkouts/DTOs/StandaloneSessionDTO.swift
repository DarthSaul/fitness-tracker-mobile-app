import Foundation

/// Bare standalone session record. Standalone flows only ever produce
/// IN_PROGRESS / COMPLETED, but `SessionStatus` covers the full enum anyway.
nonisolated struct StandaloneWorkoutSessionDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let userId: String
    let standaloneWorkoutId: String
    let status: SessionStatus
    let startedAt: Date
    let completedAt: Date?
    let notes: String?
}

/// POST /api/standalone-workout-sessions (201) and
/// PATCH /api/standalone-workout-sessions/:id/complete (200) both return
/// `{ session }`.
nonisolated struct StandaloneSessionResponseDTO: Codable, Sendable, Equatable {
    let session: StandaloneWorkoutSessionDTO
}

/// One row from GET /api/standalone-workout-sessions/active and /history:
/// the session enriched with `_count.completedSets` and a slim workout ref.
nonisolated struct StandaloneSessionListItemDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let userId: String
    let standaloneWorkoutId: String
    let status: SessionStatus
    let startedAt: Date
    let completedAt: Date?
    let notes: String?
    let count: Count
    let standaloneWorkout: WorkoutRef

    nonisolated struct Count: Codable, Sendable, Equatable {
        let completedSets: Int
    }

    nonisolated struct WorkoutRef: Codable, Sendable, Equatable {
        let id: String
        let category: String
        let order: Int
        let name: String?

        var displayName: String {
            standaloneWorkoutDisplayName(name: name, category: category, order: order)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, standaloneWorkoutId, status, startedAt, completedAt, notes, standaloneWorkout
        case count = "_count"
    }
}

/// `{ sessions: [...] }` wrapper shared by /active and /history.
nonisolated struct StandaloneSessionListResponseDTO: Codable, Sendable, Equatable {
    let sessions: [StandaloneSessionListItemDTO]
}

/// A logged set within a standalone session. Two flavors:
/// - **Prescribed**: `standaloneWorkoutSetId` non-nil, `adhocExerciseName` nil.
/// - **Ad-hoc**: `standaloneWorkoutSetId` nil, `adhocExerciseName` non-nil.
nonisolated struct StandaloneCompletedSetDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let standaloneWorkoutSessionId: String
    let standaloneWorkoutSetId: String?
    let adhocExerciseName: String?
    let reps: Int?
    let weight: Double?
    let rpe: Double?
    let notes: String?
    let completedAt: Date
}

/// GET /api/standalone-workout-sessions/:id returns
/// `{ session: { ...fields, completedSets }, workout: <full template> }`.
/// Works for in-progress and completed sessions (live view and history detail).
nonisolated struct StandaloneSessionDetailResponseDTO: Codable, Sendable, Equatable {
    let session: SessionWithSets
    let workout: StandaloneWorkoutDetailDTO

    nonisolated struct SessionWithSets: Codable, Sendable, Equatable, Identifiable {
        let id: String
        let userId: String
        let standaloneWorkoutId: String
        let status: SessionStatus
        let startedAt: Date
        let completedAt: Date?
        let notes: String?
        let completedSets: [StandaloneCompletedSetDTO]
    }
}
