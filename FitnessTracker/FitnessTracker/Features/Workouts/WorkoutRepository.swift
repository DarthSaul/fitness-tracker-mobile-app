import Foundation
import OSLog

/// Wraps the workout-session endpoints used by the active-program flow.
/// GET /api/workouts/:id has the same `{ session, day }` shape as
/// /api/workouts/active, so we reuse `ActiveWorkoutResponseDTO` rather than
/// minting a near-identical second type.
@MainActor
final class WorkoutRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - Create / fetch

    /// POST /api/workouts with explicit week/day → server creates an EDITING session.
    @discardableResult
    func createRetroactiveWorkout(weekNumber: Int, dayNumber: Int) async throws -> StartWorkoutResponseDTO {
        try await apiClient.send(.createWorkout(CreateWorkoutBody(weekNumber: weekNumber, dayNumber: dayNumber)))
    }

    func getWorkout(id: String) async throws -> ActiveWorkoutResponseDTO {
        try await apiClient.send(.getWorkout(id: id))
    }

    // MARK: - Set logging

    @discardableResult
    func recordSet(workoutId: String, body: RecordSetBody) async throws -> CompletedSetDTO {
        try await apiClient.send(.recordSet(workoutId: workoutId, body: body))
    }

    @discardableResult
    func updateSet(workoutId: String, setId: String, body: UpdateSetBody) async throws -> CompletedSetDTO {
        try await apiClient.send(.updateSet(workoutId: workoutId, setId: setId, body: body))
    }

    func deleteSet(workoutId: String, setId: String) async throws {
        try await apiClient.send(.deleteSet(workoutId: workoutId, setId: setId))
    }

    // MARK: - Finalize / discard

    @discardableResult
    func completeWorkout(id: String, completedAt: Date?) async throws -> CompleteWorkoutResponseDTO {
        let body = CompleteWorkoutBody(completedAt: completedAt)
        return try await apiClient.send(.completeWorkout(id: id, body: body))
    }

    func abandonWorkout(id: String) async throws {
        try await apiClient.send(.abandonWorkout(id: id))
    }
}
