import Foundation
import Testing
@testable import FitnessTracker

@Suite("HistoryViewModel")
@MainActor
struct HistoryViewModelTests {
    private func makeSession(
        id: String,
        completedAt: Date
    ) -> HistorySessionDTO {
        HistorySessionDTO(
            id: id, userId: "u1", userProgramId: "up1",
            programName: "Strength Base",
            weekNumber: 1, dayNumber: 1, status: .completed,
            startedAt: completedAt, completedAt: completedAt, notes: nil,
            count: HistorySessionDTO.Count(completedSets: 5)
        )
    }

    private func makeViewModel(pageSize: Int = 2) -> (HistoryViewModel, MockAPIClient) {
        let client = MockAPIClient()
        let repo = HistoryRepository(apiClient: client)
        let session = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        let vm = HistoryViewModel(
            repository: repo, sessionManager: session, pageSize: pageSize
        )
        return (vm, client)
    }

    @Test("load populates sessions and clears reachedEnd when full page returned")
    func loadFullPage() async throws {
        let (vm, client) = makeViewModel(pageSize: 2)
        let s1 = makeSession(id: "a", completedAt: Date(timeIntervalSince1970: 100))
        let s2 = makeSession(id: "b", completedAt: Date(timeIntervalSince1970: 90))
        client.stub(
            .getWorkoutHistory(limit: 2, before: nil, beforeId: nil),
            response: WorkoutHistoryResponseDTO(sessions: [s1, s2])
        )

        await vm.load()

        #expect(vm.sessions.count == 2)
        #expect(vm.sessions[0].id == "a")
        #expect(vm.reachedEnd == false)
        #expect(vm.loadError == nil)
    }

    @Test("load marks reachedEnd when partial page returned")
    func loadPartialPage() async throws {
        let (vm, client) = makeViewModel(pageSize: 5)
        client.stub(
            .getWorkoutHistory(limit: 5, before: nil, beforeId: nil),
            response: WorkoutHistoryResponseDTO(sessions: [
                makeSession(id: "a", completedAt: Date(timeIntervalSince1970: 100))
            ])
        )

        await vm.load()

        #expect(vm.sessions.count == 1)
        #expect(vm.reachedEnd == true)
    }

    @Test("loadMore uses the last session's completedAt as cursor")
    func loadMoreCursor() async throws {
        let (vm, client) = makeViewModel(pageSize: 2)
        let firstPage = [
            makeSession(id: "a", completedAt: Date(timeIntervalSince1970: 200)),
            makeSession(id: "b", completedAt: Date(timeIntervalSince1970: 100)),
        ]
        let secondPage = [
            makeSession(id: "c", completedAt: Date(timeIntervalSince1970: 50)),
        ]
        client.stub(
            .getWorkoutHistory(limit: 2, before: nil, beforeId: nil),
            response: WorkoutHistoryResponseDTO(sessions: firstPage)
        )
        await vm.load()

        // Capture the cursor passed on the next fetch.
        var capturedBefore: Date?
        var capturedBeforeId: String?
        client.handlers["GET /api/workouts/history"] = { endpoint in
            if case .getWorkoutHistory(_, let before, let beforeId) = endpoint {
                capturedBefore = before
                capturedBeforeId = beforeId
            }
            return try JSONCoding.encoder.encode(WorkoutHistoryResponseDTO(sessions: secondPage))
        }

        await vm.loadMore()

        #expect(capturedBefore == Date(timeIntervalSince1970: 100))
        #expect(capturedBeforeId == "b")
        #expect(vm.sessions.map(\.id) == ["a", "b", "c"])
        #expect(vm.reachedEnd == true) // 1 < pageSize 2
    }

    @Test("loadMore is a no-op when reachedEnd")
    func loadMoreNoOpAtEnd() async throws {
        let (vm, client) = makeViewModel(pageSize: 5)
        client.stub(
            .getWorkoutHistory(limit: 5, before: nil, beforeId: nil),
            response: WorkoutHistoryResponseDTO(sessions: [
                makeSession(id: "a", completedAt: Date(timeIntervalSince1970: 100))
            ])
        )
        await vm.load()
        #expect(vm.reachedEnd == true)

        // Replace the handler with one that explodes if called — guard ensures
        // loadMore actually short-circuits.
        client.handlers["GET /api/workouts/history"] = { _ in
            Issue.record("loadMore should not call the API after reachedEnd")
            throw APIError.missingHandler(path: "/api/workouts/history")
        }

        await vm.loadMore()
        #expect(vm.sessions.count == 1)
    }
}
