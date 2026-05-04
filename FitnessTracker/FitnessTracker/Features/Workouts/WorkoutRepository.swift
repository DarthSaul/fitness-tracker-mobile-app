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

    /// GET /api/workouts/active. Returns nil on 404 (no in-progress session).
    func getActiveWorkout() async throws -> ActiveWorkoutResponseDTO? {
        do {
            let dto: ActiveWorkoutResponseDTO = try await apiClient.send(.getActiveWorkout)
            return dto
        } catch let error where Self.isNotFound(error) {
            return nil
        }
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

    // MARK: - Extra sets / ad-hoc / swap (live-workout only)

    @discardableResult
    func addExtraSet(workoutId: String, programExerciseId: String, body: AddExtraSetBody) async throws -> CompletedSetDTO {
        try await apiClient.send(.addExtraSet(workoutId: workoutId, programExerciseId: programExerciseId, body: body))
    }

    func deleteExtraSet(workoutId: String, completedSetId: String) async throws {
        try await apiClient.send(.deleteExtraSet(workoutId: workoutId, completedSetId: completedSetId))
    }

    @discardableResult
    func swapExercise(workoutId: String, programExerciseId: String, replacementExerciseId: String) async throws -> SwapExerciseResponseDTO {
        let body = SwapExerciseBody(replacementExerciseId: replacementExerciseId)
        return try await apiClient.send(.swapExercise(workoutId: workoutId, programExerciseId: programExerciseId, body: body))
    }

    @discardableResult
    func addAdHocSet(workoutId: String, exerciseName: String) async throws -> CompletedSetDTO {
        let body = AddAdHocSetBody(exerciseName: exerciseName)
        return try await apiClient.send(.addAdHocSet(workoutId: workoutId, body: body))
    }

    @discardableResult
    func updateNotes(workoutId: String, notes: String) async throws -> UpdateWorkoutNotesResponseDTO {
        let body = UpdateWorkoutNotesBody(notes: notes)
        return try await apiClient.send(.updateWorkoutNotes(id: workoutId, body: body))
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

    // MARK: - Helpers
    private static func isNotFound(_ error: any Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        if case .httpError(let statusCode, _) = apiError, statusCode == 404 {
            return true
        }
        return false
    }
}
