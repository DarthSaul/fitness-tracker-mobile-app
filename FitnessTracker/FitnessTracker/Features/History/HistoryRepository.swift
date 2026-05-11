import Foundation

@MainActor
final class HistoryRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    /// GET /api/workouts/history. `limit` defaults to the server-side default
    /// (20) when nil. `before` is a cursor — pass the last loaded session's
    /// `completedAt` to fetch the next older page.
    func fetchHistory(limit: Int? = nil, before: Date? = nil) async throws -> [HistorySessionDTO] {
        let response: WorkoutHistoryResponseDTO = try await apiClient.send(
            .getWorkoutHistory(limit: limit, before: before)
        )
        return response.sessions
    }
}
