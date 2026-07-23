import Foundation
import Testing
@testable import FitnessTracker

@Suite("StandaloneWorkoutListViewModel")
@MainActor
struct StandaloneWorkoutListViewModelTests {
    // MARK: - Fixtures

    private func makeSummary(id: String, category: String, order: Int, name: String? = nil) -> StandaloneWorkoutSummaryDTO {
        StandaloneWorkoutSummaryDTO(
            id: id, category: category, order: order, name: name, description: nil,
            createdAt: .now, count: StandaloneWorkoutSummaryDTO.Count(groups: 3)
        )
    }

    private func makeListItem(id: String, workoutId: String) -> StandaloneSessionListItemDTO {
        StandaloneSessionListItemDTO(
            id: id, userId: "u1", standaloneWorkoutId: workoutId,
            status: .inProgress, startedAt: .now, completedAt: nil, notes: nil,
            count: StandaloneSessionListItemDTO.Count(completedSets: 0),
            standaloneWorkout: StandaloneSessionListItemDTO.WorkoutRef(
                id: workoutId, category: "Arms Only", order: 1, name: nil
            )
        )
    }

    private func makeViewModel(client: MockAPIClient) -> StandaloneWorkoutListViewModel {
        StandaloneWorkoutListViewModel(
            repository: StandaloneWorkoutRepository(apiClient: client),
            sessionManager: SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        )
    }

    // MARK: - Tests

    @Test("groupedByCategory preserves the server's category and order sequence")
    func grouping() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneWorkouts(category: nil), response: [
            makeSummary(id: "a1", category: "Arms Only", order: 1),
            makeSummary(id: "a2", category: "Arms Only", order: 2),
            makeSummary(id: "d1", category: "DB Only", order: 1)
        ])
        client.stub(.getActiveStandaloneSessions, response: StandaloneSessionListResponseDTO(sessions: []))
        let vm = makeViewModel(client: client)

        await vm.load()

        let groups = vm.groupedByCategory
        #expect(groups.map(\.category) == ["Arms Only", "DB Only"])
        #expect(groups[0].workouts.map(\.id) == ["a1", "a2"])
        #expect(groups[1].workouts.map(\.id) == ["d1"])
    }

    @Test("activeSession(forWorkoutId:) matches sessions to catalog rows")
    func activeBadges() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneWorkouts(category: nil), response: [
            makeSummary(id: "a1", category: "Arms Only", order: 1),
            makeSummary(id: "a2", category: "Arms Only", order: 2)
        ])
        client.stub(
            .getActiveStandaloneSessions,
            response: StandaloneSessionListResponseDTO(sessions: [makeListItem(id: "ss1", workoutId: "a2")])
        )
        let vm = makeViewModel(client: client)

        await vm.load()

        #expect(vm.activeSession(forWorkoutId: "a1") == nil)
        #expect(vm.activeSession(forWorkoutId: "a2")?.id == "ss1")
    }

    @Test("a failed active-sessions fetch still shows the catalog")
    func activeFailureNonFatal() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneWorkouts(category: nil), response: [
            makeSummary(id: "a1", category: "Arms Only", order: 1)
        ])
        client.handlers["GET /api/standalone-workout-sessions/active"] = { _ in
            throw APIError.httpError(statusCode: 500, message: nil, data: Data())
        }
        let vm = makeViewModel(client: client)

        await vm.load()

        #expect(vm.workouts.count == 1)
        #expect(vm.loadError == nil)
        #expect(vm.activeSessions.isEmpty)
    }
}
