import Foundation
import Testing
@testable import FitnessTracker

@Suite("StandaloneHistoryViewModel")
@MainActor
struct StandaloneHistoryViewModelTests {
    // MARK: - Fixtures

    private func makeCompleted(id: String, completedAt: Date) -> StandaloneSessionListItemDTO {
        StandaloneSessionListItemDTO(
            id: id, userId: "u1", standaloneWorkoutId: "sw1",
            status: .completed, startedAt: completedAt.addingTimeInterval(-1800),
            completedAt: completedAt, notes: nil,
            count: StandaloneSessionListItemDTO.Count(completedSets: 8),
            standaloneWorkout: StandaloneSessionListItemDTO.WorkoutRef(
                id: "sw1", category: "Total Body", order: 1, name: nil
            )
        )
    }

    private func makeViewModel(client: MockAPIClient, pageSize: Int = 2) -> StandaloneHistoryViewModel {
        StandaloneHistoryViewModel(
            repository: StandaloneWorkoutRepository(apiClient: client),
            sessionManager: SessionManager(keychain: KeychainService(), tokenStore: TokenStore()),
            pageSize: pageSize
        )
    }

    // MARK: - Tests

    @Test("loadMore pages with the last row's completedAt + id and stops at the end")
    func pagination() async throws {
        let client = MockAPIClient()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = t1.addingTimeInterval(-3600)
        let t3 = t2.addingTimeInterval(-3600)
        let page1 = [makeCompleted(id: "ss1", completedAt: t1), makeCompleted(id: "ss2", completedAt: t2)]
        let page2 = [makeCompleted(id: "ss3", completedAt: t3)]

        client.handlers["GET /api/standalone-workout-sessions/history"] = { endpoint in
            guard case .getStandaloneSessionHistory(_, let before, let beforeId) = endpoint else {
                throw APIError.missingHandler(path: "unexpected endpoint")
            }
            if before == nil {
                return try JSONCoding.encoder.encode(StandaloneSessionListResponseDTO(sessions: page1))
            }
            #expect(beforeId == "ss2")
            return try JSONCoding.encoder.encode(StandaloneSessionListResponseDTO(sessions: page2))
        }
        let vm = makeViewModel(client: client, pageSize: 2)

        await vm.load()
        #expect(vm.sessions.map(\.id) == ["ss1", "ss2"])
        #expect(vm.reachedEnd == false)

        await vm.loadMore()
        #expect(vm.sessions.map(\.id) == ["ss1", "ss2", "ss3"])
        // Short page → end reached; further loadMore calls are no-ops.
        #expect(vm.reachedEnd == true)
        await vm.loadMore()
        #expect(vm.sessions.count == 3)
    }
}
