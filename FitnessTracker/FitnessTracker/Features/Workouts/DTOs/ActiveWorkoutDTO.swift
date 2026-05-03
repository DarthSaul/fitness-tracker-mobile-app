import Foundation

/// GET /api/workouts/active returns `{ session, day }`. The session embeds
/// `completedSets`, the originating `userProgram`, and the active
/// `workoutExerciseSwaps`. Swaps are also pre-applied to `day.exerciseGroups[].exercises[].exercise`.
nonisolated struct ActiveWorkoutResponseDTO: Codable, Sendable, Equatable {
    let session: ActiveWorkoutSession
    let day: ProgramDayDTO

    nonisolated struct ActiveWorkoutSession: Codable, Sendable, Equatable, Identifiable {
        let id: String
        let userId: String
        let userProgramId: String
        let weekNumber: Int
        let dayNumber: Int
        let status: SessionStatus
        let startedAt: Date
        let completedAt: Date?
        let notes: String?
        let completedSets: [CompletedSetDTO]
        let userProgram: UserProgramDTO
        let workoutExerciseSwaps: [WorkoutExerciseSwapDTO]
    }
}

/// POST /api/workouts returns `{ session, day }`.
nonisolated struct StartWorkoutResponseDTO: Codable, Sendable, Equatable {
    let session: WorkoutSessionDTO
    let day: ProgramDayDTO
}

/// PATCH /api/workouts/[id]/complete returns `{ session, userProgram, programCompleted }`.
nonisolated struct CompleteWorkoutResponseDTO: Codable, Sendable, Equatable {
    let session: WorkoutSessionDTO
    let userProgram: UserProgramDTO
    let programCompleted: Bool
}

/// PATCH /api/workouts/[id] (notes update) returns `{ id, notes }`.
nonisolated struct UpdateWorkoutNotesResponseDTO: Codable, Sendable, Equatable {
    let id: String
    let notes: String?
}
