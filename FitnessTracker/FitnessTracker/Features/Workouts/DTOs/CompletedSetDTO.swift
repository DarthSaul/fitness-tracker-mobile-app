import Foundation

/// A logged set within a workout session. Three flavors share this type:
/// - **Template set**: `exerciseSetId` non-nil, `programExerciseId` nil, `adhocExerciseName` nil.
/// - **Extra set**: `exerciseSetId` nil, `programExerciseId` non-nil, `adhocExerciseName` nil.
/// - **Ad-hoc set**: both IDs nil, `adhocExerciseName` non-nil.
nonisolated struct CompletedSetDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let workoutSessionId: String
    let exerciseSetId: String?
    let programExerciseId: String?
    let adhocExerciseName: String?
    let reps: Int?
    let weight: Double?
    let rpe: Double?
    let notes: String?
    let completedAt: Date
}
