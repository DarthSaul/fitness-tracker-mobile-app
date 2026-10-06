import Foundation

/// Thin wrapper around the three `/api/analytics/*` endpoints, plus the
/// completion timestamps the weekly-volume chart buckets on the device.
@MainActor
final class AnalyticsRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    /// `sessionsThisWeek` counts the user's week (their `weekStartDay`) in
    /// `timeZone`, the device's zone unless given. Sent as an IANA name
    /// rather than an offset so the server gets DST weeks right.
    func fetchDashboard(timeZone: TimeZone? = nil) async throws -> AnalyticsDashboardDTO {
        let identifier = (timeZone ?? .current).identifier
        return try await apiClient.send(.getDashboard(timeZone: identifier))
    }

    func fetchExercises() async throws -> [AnalyticsExerciseDTO] {
        try await apiClient.send(.getAnalyticsExercises)
    }

    /// GET /api/history/dates — every completed session's `completedAt`
    /// (program and standalone), oldest first.
    func fetchCompletionDates() async throws -> [Date] {
        let response: HistoryDatesResponseDTO = try await apiClient.send(.getHistoryDates)
        return response.completedAt
    }

    func fetchExerciseHistory(id: String) async throws -> AnalyticsExerciseHistoryDTO {
        try await apiClient.send(.getAnalyticsExercise(id: id))
    }
}
