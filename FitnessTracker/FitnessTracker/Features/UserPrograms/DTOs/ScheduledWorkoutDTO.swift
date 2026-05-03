import Foundation

nonisolated struct ScheduledWorkoutDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let userProgramId: String
    let weekNumber: Int
    let dayNumber: Int
    let scheduledDate: Date
    let createdAt: Date
}

/// GET /api/scheduled-workouts wraps the list under "scheduledWorkouts".
nonisolated struct ScheduledWorkoutsResponseDTO: Codable, Sendable, Equatable {
    let scheduledWorkouts: [ScheduledWorkoutDTO]
}

/// POST /api/scheduled-workouts wraps the created record under "scheduledWorkout".
nonisolated struct ScheduleWorkoutResponseDTO: Codable, Sendable, Equatable {
    let scheduledWorkout: ScheduledWorkoutDTO
}
