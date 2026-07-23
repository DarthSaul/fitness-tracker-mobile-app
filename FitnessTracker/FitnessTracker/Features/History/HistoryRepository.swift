import Foundation

@MainActor
final class HistoryRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    /// GET /api/history — completed sessions across program and standalone
    /// workouts, interleaved newest-first (pass `type` to narrow to one kind).
    /// `limit` defaults to the server-side default (20) when nil. The cursor is
    /// the last loaded row's `completedAt` + `id`; the server requires both
    /// together, so pass them as a pair (or neither, for the first page).
    func fetchHistory(
        type: HistoryTypeFilter? = nil,
        limit: Int? = nil,
        before: Date? = nil,
        beforeId: String? = nil
    ) async throws -> [HistoryEntryDTO] {
        let response: HistoryResponseDTO = try await apiClient.send(
            .getHistory(type: type, limit: limit, before: before, beforeId: beforeId)
        )
        return response.sessions
    }
}
