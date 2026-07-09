import Foundation

/// A saved "core" circuit attached to a workout session (server-backed).
///
/// Wire shape from `PUT /api/workouts/:sessionId/core-workout`, and folded into
/// the active-workout / history session as `session.coreWorkout` (nil when no
/// circuit is saved). `timeSeconds` is the per-set work duration, `restSeconds`
/// the per-set rest; the number of sets is `exercises.count`.
nonisolated struct CoreWorkoutDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let workoutSessionId: String
    let timeSeconds: Int
    let restSeconds: Int
    /// Set when the user finishes the timer; nil while unstarted / ended early.
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let exercises: [CoreWorkoutExerciseDTO]

    /// Catalog exercises in circuit order (1-based `order`).
    var orderedExercises: [ExerciseDTO] {
        exercises.sorted { $0.order < $1.order }.map(\.exercise)
    }
}

/// One ordered entry in a core circuit. `order` is 1-based; `exercise` is the
/// catalog exercise (id + name; `description` is omitted in this nested shape,
/// so it decodes to nil).
nonisolated struct CoreWorkoutExerciseDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let order: Int
    let exercise: ExerciseDTO
}
