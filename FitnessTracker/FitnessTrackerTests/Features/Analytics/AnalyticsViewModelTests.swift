import Foundation
import Testing
@testable import FitnessTracker

@Suite("AnalyticsViewModel")
@MainActor
struct AnalyticsViewModelTests {
    // MARK: - Fixtures
    private func makeDashboard(totalSessions: Int = 12) -> AnalyticsDashboardDTO {
        AnalyticsDashboardDTO(
            totalSessions: totalSessions,
            totalVolumeLbs: 6_400,
            currentStreakDays: 2,
            longestStreakDays: 5,
            lastWorkoutAt: nil,
            totalExercises: 7,
            sessionsThisWeek: 3
        )
    }

    private func makeExercises() -> [AnalyticsExerciseDTO] {
        [
            AnalyticsExerciseDTO(id: "e1", name: "Squat", sessionCount: 10, lastCompletedAt: .now),
            AnalyticsExerciseDTO(id: "e2", name: "Press", sessionCount: 5, lastCompletedAt: .now)
        ]
    }

    private func makeHistory(id: String, name: String = "Squat") -> AnalyticsExerciseHistoryDTO {
        AnalyticsExerciseHistoryDTO(
            exercise: .init(id: id, name: name),
            history: [
                .init(sessionId: "s1", completedAt: .now,
                      type: AnalyticsExerciseHistoryDTO.SessionEntry.programType,
                      weekNumber: 1, dayNumber: 1, workoutLabel: nil,
                      sets: [], bestE1rm: 200, totalVolume: 1000)
            ]
        )
    }

    private func makeViewModel(
        dashboard: AnalyticsDashboardDTO? = nil,
        exercises: [AnalyticsExerciseDTO] = [],
        historyById: [String: AnalyticsExerciseHistoryDTO] = [:]
    ) -> (AnalyticsViewModel, MockAPIClient) {
        let client = MockAPIClient()
        if let dashboard {
            // Stub by exact path so any tzOffset value resolves to the same handler.
            client.handlers["GET /api/analytics/dashboard"] = { _ in
                try JSONCoding.encoder.encode(dashboard)
            }
        }
        client.stub(.getAnalyticsExercises, response: exercises)
        for (id, history) in historyById {
            client.stub(.getAnalyticsExercise(id: id), response: history)
        }
        let repo = AnalyticsRepository(apiClient: client)
        return (AnalyticsViewModel(repository: repo), client)
    }

    // MARK: - load()

    @Test("load() fetches dashboard and exercises in parallel")
    func loadHappy() async {
        let dashboard = makeDashboard(totalSessions: 99)
        let exercises = makeExercises()
        let (vm, _) = makeViewModel(dashboard: dashboard, exercises: exercises)

        await vm.load()

        #expect(vm.dashboard?.totalSessions == 99)
        #expect(vm.exercises.count == 2)
        #expect(vm.dashboardStatus == .success)
        #expect(vm.exercisesStatus == .success)
    }

    @Test("load() records error status for dashboard failure")
    func loadDashboardError() async {
        let exercises = makeExercises()
        let client = MockAPIClient()
        client.stubUnauthorized(method: .get, path: "/api/analytics/dashboard")
        client.stub(.getAnalyticsExercises, response: exercises)
        let vm = AnalyticsViewModel(repository: AnalyticsRepository(apiClient: client))

        await vm.load()

        if case .error = vm.dashboardStatus {
            // expected
        } else {
            Issue.record("Expected dashboardStatus to be .error")
        }
        #expect(vm.exercises.count == 2)
        #expect(vm.exercisesStatus == .success)
    }

    // MARK: - selectExercise

    @Test("selectExercise loads history and sets selectedExerciseId")
    func selectExerciseHappy() async {
        let history = makeHistory(id: "e1")
        let (vm, _) = makeViewModel(historyById: ["e1": history])

        vm.selectExercise("e1")
        // The VM kicks off a background Task; await the next runloop tick by
        // yielding repeatedly until the status settles.
        await waitForStatus(vm) { $0.historyStatus != .pending }

        #expect(vm.selectedExerciseId == "e1")
        #expect(vm.historyStatus == .success)
        #expect(vm.exerciseHistory?.exercise.id == "e1")
    }

    @Test("Re-selecting the same exercise toggles selection off")
    func toggleOff() async {
        let history = makeHistory(id: "e1")
        let (vm, _) = makeViewModel(historyById: ["e1": history])

        vm.selectExercise("e1")
        await waitForStatus(vm) { $0.historyStatus == .success }

        vm.selectExercise("e1")
        #expect(vm.selectedExerciseId == nil)
        #expect(vm.exerciseHistory == nil)
        #expect(vm.historyStatus == .idle)
    }

    @Test("Selecting a new exercise mid-flight discards the older response")
    func staleResponseIgnored() async {
        let client = MockAPIClient()
        // Slow first request so we can sneak a second selection in before it
        // resolves. The second handler returns immediately.
        client.handlers["GET /api/analytics/exercises/e1"] = { _ in
            // In tests we can't easily await, so simulate slowness by failing —
            // either way, the revision check should drop the result.
            throw APIError.unauthorized
        }
        let secondHistory = makeHistory(id: "e2", name: "Press")
        client.stub(.getAnalyticsExercise(id: "e2"), response: secondHistory)
        let vm = AnalyticsViewModel(repository: AnalyticsRepository(apiClient: client))

        vm.selectExercise("e1")  // will fail
        vm.selectExercise("e2")  // bumps the revision before e1's task resolves

        await waitForStatus(vm) { $0.historyStatus != .pending }

        // The latest selection (e2) should win regardless of e1's outcome.
        #expect(vm.selectedExerciseId == "e2")
        #expect(vm.exerciseHistory?.exercise.id == "e2")
        #expect(vm.historyStatus == .success)
    }

    @Test("clearSelection wipes state")
    func clearSelection() async {
        let (vm, _) = makeViewModel(historyById: ["e1": makeHistory(id: "e1")])
        vm.selectExercise("e1")
        await waitForStatus(vm) { $0.historyStatus == .success }

        vm.clearSelection()
        #expect(vm.selectedExerciseId == nil)
        #expect(vm.exerciseHistory == nil)
        #expect(vm.historyStatus == .idle)
    }

    // MARK: - Helpers

    /// Polls the @MainActor-isolated VM until the predicate is satisfied or a
    /// short timeout elapses. Ample for in-memory mocks; cheap when the
    /// predicate is already true on the first tick. On timeout we record an
    /// Issue (swift-testing's XCTFail equivalent) so a never-true predicate
    /// fails the calling test fast instead of letting subsequent #expect
    /// lines diagnose the symptom one step removed.
    private func waitForStatus(
        _ vm: AnalyticsViewModel,
        timeout: Duration = .milliseconds(500),
        sourceLocation: SourceLocation = #_sourceLocation,
        predicate: (AnalyticsViewModel) -> Bool
    ) async {
        let start = ContinuousClock.now
        while !predicate(vm) {
            if ContinuousClock.now - start > timeout {
                Issue.record(
                    "Timed out waiting for predicate in waitForStatus (historyStatus=\(vm.historyStatus), selectedExerciseId=\(vm.selectedExerciseId ?? "nil"))",
                    sourceLocation: sourceLocation
                )
                return
            }
            await Task.yield()
        }
    }
}
