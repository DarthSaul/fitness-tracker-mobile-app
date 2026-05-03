import Foundation

nonisolated struct WorkoutExerciseSwapDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let workoutSessionId: String
    let programExerciseId: String
    let originalExerciseId: String
    let replacementExerciseId: String
    let createdAt: Date
}

/// POST /api/workouts/[id]/exercises/[programExerciseId]/swap response.
nonisolated struct SwapExerciseResponseDTO: Codable, Sendable, Equatable {
    let swap: WorkoutExerciseSwapDTO
    let deletedSetCount: Int
}
