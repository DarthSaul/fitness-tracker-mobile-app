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
        // `var` so the live VM can mirror a persisted notes update back onto
        // the session without a full reload (see LiveWorkoutViewModel.updateNotes).
        var notes: String?
        let completedSets: [CompletedSetDTO]
        let userProgram: UserProgramDTO
        let workoutExerciseSwaps: [WorkoutExerciseSwapDTO]
        // The saved core circuit for this session, or nil. `var` so the live VM
        // can mirror a save/complete back onto the session without a reload.
        // Defaulted so existing memberwise-init call sites (tests) stay valid.
        var coreWorkout: CoreWorkoutDTO? = nil
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

/// PATCH /api/workouts/[id] returns `{ id, notes, completedAt }` regardless of
/// which field(s) were updated. Callers pick the field they care about.
nonisolated struct UpdateWorkoutResponseDTO: Codable, Sendable, Equatable {
    let id: String
    let notes: String?
    let completedAt: Date?
}

/// Back-compat alias for the notes-update call site. Same wire shape as
/// UpdateWorkoutResponseDTO; kept so existing tests reading `.notes` continue
/// to work without churn.
typealias UpdateWorkoutNotesResponseDTO = UpdateWorkoutResponseDTO
