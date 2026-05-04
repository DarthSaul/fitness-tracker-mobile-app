import Foundation
import OSLog

@MainActor
final class HomeRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - Active program / workout
    // Server returns 404 when nothing is active. Map that to nil so the VM
    // can render the empty-state UI without treating it as an error.

    func fetchActiveUserProgram() async throws -> ActiveUserProgramDTO? {
        do {
            let dto: ActiveUserProgramDTO = try await apiClient.send(.getActiveUserProgram)
            return dto
        } catch let error where Self.isNotFound(error) {
            return nil
        }
    }

    func fetchActiveWorkout() async throws -> ActiveWorkoutResponseDTO? {
        do {
            let dto: ActiveWorkoutResponseDTO = try await apiClient.send(.getActiveWorkout)
            return dto
        } catch let error where Self.isNotFound(error) {
            return nil
        }
    }

    // MARK: - Sessions / scheduled workouts

    func fetchActiveProgramSessions() async throws -> [ActiveProgramSessionDTO] {
        do {
            let response: ActiveProgramSessionsResponseDTO = try await apiClient.send(.getActiveProgramSessions)
            return response.sessions
        } catch let error where Self.isNotFound(error) {
            // No active program → no sessions. Surface as empty rather than error.
            return []
        }
    }

    func fetchScheduledWorkouts(
        userProgramId: String,
        from: Date? = nil,
        to: Date? = nil
    ) async throws -> [ScheduledWorkoutDTO] {
        let response: ScheduledWorkoutsResponseDTO = try await apiClient.send(
            .getScheduledWorkouts(userProgramId: userProgramId, from: from, to: to)
        )
        return response.scheduledWorkouts
    }

    // MARK: - Mutations

    @discardableResult
    func scheduleWorkout(
        userProgramId: String,
        weekNumber: Int,
        dayNumber: Int,
        scheduledDate: Date
    ) async throws -> ScheduledWorkoutDTO {
        let response: ScheduleWorkoutResponseDTO = try await apiClient.send(
            .scheduleWorkout(ScheduleWorkoutBody(
                userProgramId: userProgramId,
                weekNumber: weekNumber,
                dayNumber: dayNumber,
                scheduledDate: scheduledDate
            ))
        )
        return response.scheduledWorkout
    }

    func unscheduleWorkout(id: String) async throws {
        try await apiClient.send(.unscheduleWorkout(id: id))
    }

    @discardableResult
    func startWorkout(weekNumber: Int? = nil, dayNumber: Int? = nil) async throws -> StartWorkoutResponseDTO {
        let body: CreateWorkoutBody?
        if let weekNumber, let dayNumber {
            body = CreateWorkoutBody(weekNumber: weekNumber, dayNumber: dayNumber)
        } else {
            body = nil
        }
        return try await apiClient.send(.createWorkout(body))
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
