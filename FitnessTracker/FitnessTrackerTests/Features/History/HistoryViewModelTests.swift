import Foundation
import Testing
@testable import FitnessTracker

@Suite("HistoryViewModel")
@MainActor
struct HistoryViewModelTests {
    private func makeProgramEntry(
        id: String,
        completedAt: Date
    ) -> HistoryEntryDTO {
        .program(HistorySessionDTO(
            id: id, userId: "u1", userProgramId: "up1",
            programName: "Strength Base",
            weekNumber: 1, dayNumber: 1, status: .completed,
            startedAt: completedAt, completedAt: completedAt, notes: nil,
            count: HistorySessionDTO.Count(completedSets: 5)
        ))
    }

    private func makeStandaloneEntry(
        id: String,
        completedAt: Date
    ) -> HistoryEntryDTO {
        .standalone(StandaloneSessionListItemDTO(
            id: id, userId: "u1", standaloneWorkoutId: "sw1",
            status: .completed, startedAt: completedAt, completedAt: completedAt, notes: nil,
            count: StandaloneSessionListItemDTO.Count(completedSets: 3),
            standaloneWorkout: StandaloneSessionListItemDTO.WorkoutRef(
                id: "sw1", category: "KB Only", order: 1, name: nil
            )
        ))
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

    @Test("load populates interleaved rows and clears reachedEnd when full page returned")
    func loadFullPage() async throws {
        let (vm, client) = makeViewModel(pageSize: 2)
        let e1 = makeProgramEntry(id: "a", completedAt: Date(timeIntervalSince1970: 100))
        let e2 = makeStandaloneEntry(id: "b", completedAt: Date(timeIntervalSince1970: 90))
        client.stub(
            .getHistory(type: nil, limit: 2, before: nil, beforeId: nil),
            response: HistoryResponseDTO(sessions: [e1, e2])
        )

        await vm.load()

        #expect(vm.sessions.count == 2)
        #expect(vm.sessions[0].id == "a")
        #expect(vm.sessions[1].id == "b")
        #expect(vm.reachedEnd == false)
        #expect(vm.loadError == nil)
    }

    @Test("load marks reachedEnd when partial page returned")
    func loadPartialPage() async throws {
        let (vm, client) = makeViewModel(pageSize: 5)
        client.stub(
            .getHistory(type: nil, limit: 5, before: nil, beforeId: nil),
            response: HistoryResponseDTO(sessions: [
                makeProgramEntry(id: "a", completedAt: Date(timeIntervalSince1970: 100))
            ])
        )

        await vm.load()

        #expect(vm.sessions.count == 1)
        #expect(vm.reachedEnd == true)
    }

    @Test("loadMore uses the last row's completedAt as cursor, across row types")
    func loadMoreCursor() async throws {
        let (vm, client) = makeViewModel(pageSize: 2)
        let firstPage = [
            makeProgramEntry(id: "a", completedAt: Date(timeIntervalSince1970: 200)),
            makeStandaloneEntry(id: "b", completedAt: Date(timeIntervalSince1970: 100)),
        ]
        let secondPage = [
            makeProgramEntry(id: "c", completedAt: Date(timeIntervalSince1970: 50)),
        ]
        client.stub(
            .getHistory(type: nil, limit: 2, before: nil, beforeId: nil),
            response: HistoryResponseDTO(sessions: firstPage)
        )
        await vm.load()

        // Capture the cursor passed on the next fetch — the last row is a
        // standalone entry, so the cursor must come through the shared accessors.
        var capturedBefore: Date?
        var capturedBeforeId: String?
        client.handlers["GET /api/history"] = { endpoint in
            if case .getHistory(_, _, let before, let beforeId) = endpoint {
                capturedBefore = before
                capturedBeforeId = beforeId
            }
            return try JSONCoding.encoder.encode(HistoryResponseDTO(sessions: secondPage))
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
            .getHistory(type: nil, limit: 5, before: nil, beforeId: nil),
            response: HistoryResponseDTO(sessions: [
                makeProgramEntry(id: "a", completedAt: Date(timeIntervalSince1970: 100))
            ])
        )
        await vm.load()
        #expect(vm.reachedEnd == true)

        // Replace the handler with one that explodes if called — guard ensures
        // loadMore actually short-circuits.
        client.handlers["GET /api/history"] = { _ in
            Issue.record("loadMore should not call the API after reachedEnd")
            throw APIError.missingHandler(path: "/api/history")
        }

        await vm.loadMore()
        #expect(vm.sessions.count == 1)
    }

    // MARK: - Calendar

    private let day: TimeInterval = 86_400
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    /// Pages newest-first from `entries`, honoring the cursor.
    private func stubPaged(_ client: MockAPIClient, _ entries: [HistoryEntryDTO]) {
        client.handlers["GET /api/history"] = { endpoint in
            guard case .getHistory(_, let limit, let before, let beforeId) = endpoint else { return Data() }
            var rows = entries
            if let before, let beforeId, let index = rows.firstIndex(where: { $0.id == beforeId && $0.completedAt == before }) {
                rows = Array(rows[(index + 1)...])
            }
            return try JSONCoding.encoder.encode(HistoryResponseDTO(sessions: Array(rows.prefix(limit ?? 20))))
        }
    }

    @Test("load fills the calendar from the completion dates")
    func calendarFromDates() async throws {
        let (vm, client) = makeViewModel(pageSize: 5)
        stubPaged(client, [makeProgramEntry(id: "a", completedAt: base)])
        client.stub(.getHistoryDates, response: HistoryDatesResponseDTO(completedAt: [base, base.addingTimeInterval(-3 * day)]))

        await vm.load()

        #expect(vm.workoutCalendar.hasWorkout(on: base))
        #expect(vm.workoutCalendar.hasWorkout(on: base.addingTimeInterval(-3 * day)))
    }

    @Test("a failed dates call still shows the list")
    func datesFailureKeepsList() async throws {
        let (vm, client) = makeViewModel(pageSize: 5)
        stubPaged(client, [makeProgramEntry(id: "a", completedAt: base)])
        client.stubHTTPError(.getHistoryDates, status: 500)

        await vm.load()

        #expect(vm.sessions.map(\.id) == ["a"])
        #expect(vm.loadError == nil)
    }

    @Test("tapping a day pages back until that day's workout is loaded")
    func revealPagesToDay() async throws {
        let (vm, client) = makeViewModel(pageSize: 2)
        let entries = (0..<6).map { makeProgramEntry(id: "s\($0)", completedAt: base.addingTimeInterval(-Double($0) * day)) }
        stubPaged(client, entries)
        await vm.load()
        #expect(vm.sessions.count == 2)

        let id = await vm.reveal(day: base.addingTimeInterval(-4 * day))

        #expect(id == "s4")
        #expect(vm.sessions.count >= 5)
        #expect(vm.selectedDay != nil)
    }

    @Test("tapping a day with nothing loaded for it stops once history passes it")
    func revealStopsWhenPassed() async throws {
        let (vm, client) = makeViewModel(pageSize: 2)
        // Workouts every other day; the tapped day has none.
        let entries = (0..<4).map { makeProgramEntry(id: "s\($0)", completedAt: base.addingTimeInterval(-Double($0 * 2) * day)) }
        stubPaged(client, entries)
        await vm.load()

        let id = await vm.reveal(day: base.addingTimeInterval(-3 * day))

        #expect(id == nil)
        #expect(vm.sessions.count < 4 || vm.reachedEnd)
    }
}
