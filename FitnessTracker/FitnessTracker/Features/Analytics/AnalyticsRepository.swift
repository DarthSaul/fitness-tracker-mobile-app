import Foundation

/// Thin wrapper around the three `/api/analytics/*` endpoints.
@MainActor
final class AnalyticsRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchDashboard(tzOffsetMinutes: Int? = nil) async throws -> AnalyticsDashboardDTO {
        // Default to the device's current timezone offset when the caller
        // doesn't supply one. Computed lazily here (not as a default arg)
        // because default values evaluate outside the main actor.
        let offset = tzOffsetMinutes ?? Self.localTzOffsetMinutes()
        return try await apiClient.send(.getDashboard(tzOffsetMinutes: offset))
    }

    func fetchExercises() async throws -> [AnalyticsExerciseDTO] {
        try await apiClient.send(.getAnalyticsExercises)
    }

    func fetchExerciseHistory(id: String) async throws -> AnalyticsExerciseHistoryDTO {
        try await apiClient.send(.getAnalyticsExercise(id: id))
    }

    /// Server expects `tzOffset` in minutes-east-of-UTC (matches JS
    /// `-getTimezoneOffset()`). `TimeZone.secondsFromGMT()` already returns the
    /// signed offset in seconds-east-of-UTC, so just divide.
    static func localTzOffsetMinutes(timeZone: TimeZone = .current) -> Int {
        timeZone.secondsFromGMT() / 60
    }
}
