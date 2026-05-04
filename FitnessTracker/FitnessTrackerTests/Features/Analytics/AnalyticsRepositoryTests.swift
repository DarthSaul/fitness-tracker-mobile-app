import Foundation
import Testing
@testable import FitnessTracker

@Suite("AnalyticsRepository")
@MainActor
struct AnalyticsRepositoryTests {
    // MARK: - Fixtures
    private func makeDashboard() -> AnalyticsDashboardDTO {
        AnalyticsDashboardDTO(
            totalSessions: 42,
            totalVolumeLbs: 12_500,
            currentStreakDays: 3,
            longestStreakDays: 7,
            lastWorkoutAt: Date(timeIntervalSince1970: 1_700_000_000),
            totalExercises: 11,
            sessionsThisWeek: 4
        )
    }

    private func makeExerciseList() -> [AnalyticsExerciseDTO] {
        [
            AnalyticsExerciseDTO(id: "e1", name: "Back Squat", sessionCount: 12, lastCompletedAt: .now),
            AnalyticsExerciseDTO(id: "e2", name: "Bench Press", sessionCount: 8, lastCompletedAt: .now)
        ]
    }

    private func makeHistory(id: String = "e1") -> AnalyticsExerciseHistoryDTO {
        AnalyticsExerciseHistoryDTO(
            exercise: .init(id: id, name: "Back Squat"),
            history: [
                .init(
                    sessionId: "s1",
                    completedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    weekNumber: 1, dayNumber: 1,
                    sets: [.init(reps: 5, weight: 225, e1rm: 262.5)],
                    bestE1rm: 262.5,
                    totalVolume: 1125
                )
            ]
        )
    }

    // MARK: - 200 happy paths

    @Test("fetchDashboard sends GET to /api/analytics/dashboard with tzOffset")
    func fetchDashboard() async throws {
        let client = MockAPIClient()
        client.stub(.getDashboard(tzOffsetMinutes: 0), response: makeDashboard())
        let repo = AnalyticsRepository(apiClient: client)

        let dto = try await repo.fetchDashboard(tzOffsetMinutes: 0)
        #expect(dto.totalSessions == 42)
        #expect(dto.sessionsThisWeek == 4)
    }

    @Test("fetchExercises decodes the exercise list")
    func fetchExercises() async throws {
        let client = MockAPIClient()
        client.stub(.getAnalyticsExercises, response: makeExerciseList())
        let repo = AnalyticsRepository(apiClient: client)

        let list = try await repo.fetchExercises()
        #expect(list.count == 2)
        #expect(list[0].name == "Back Squat")
        #expect(list[0].sessionCount == 12)
    }

    @Test("fetchExerciseHistory routes by id")
    func fetchHistory() async throws {
        let client = MockAPIClient()
        client.stub(.getAnalyticsExercise(id: "e1"), response: makeHistory())
        let repo = AnalyticsRepository(apiClient: client)

        let dto = try await repo.fetchExerciseHistory(id: "e1")
        #expect(dto.exercise.id == "e1")
        #expect(dto.history.count == 1)
        #expect(dto.history[0].bestE1rm == 262.5)
    }

    // MARK: - Errors

    @Test("fetchDashboard propagates 401")
    func dashboardUnauthorized() async {
        let client = MockAPIClient()
        client.stubUnauthorized(for: .getDashboard(tzOffsetMinutes: 0))
        let repo = AnalyticsRepository(apiClient: client)

        do {
            _ = try await repo.fetchDashboard(tzOffsetMinutes: 0)
            Issue.record("Expected unauthorized error")
        } catch let error as APIError {
            if case .unauthorized = error {
                // expected
            } else {
                Issue.record("Expected .unauthorized, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Timezone offset

    @Test("localTzOffsetMinutes converts seconds-east-of-UTC to minutes")
    func tzOffsetConversion() {
        // -5h (e.g. New York standard time)
        let est = TimeZone(secondsFromGMT: -5 * 3600)!
        #expect(AnalyticsRepository.localTzOffsetMinutes(timeZone: est) == -300)
        // +9h (Tokyo)
        let jst = TimeZone(secondsFromGMT: 9 * 3600)!
        #expect(AnalyticsRepository.localTzOffsetMinutes(timeZone: jst) == 540)
    }
}
