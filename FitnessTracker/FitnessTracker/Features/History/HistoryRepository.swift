import Foundation

@MainActor
final class HistoryRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    /// GET /api/workouts/history. `limit` defaults to the server-side default
    /// (20) when nil. The cursor is the last loaded session's `completedAt` +
    /// `id`; the server requires both together, so pass them as a pair (or
    /// neither, for the first page).
    func fetchHistory(limit: Int? = nil, before: Date? = nil, beforeId: String? = nil) async throws -> [HistorySessionDTO] {
        let response: WorkoutHistoryResponseDTO = try await apiClient.send(
            .getWorkoutHistory(limit: limit, before: before, beforeId: beforeId)
        )
        return response.sessions
    }
}
