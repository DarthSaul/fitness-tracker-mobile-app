import Foundation
import Testing
@testable import FitnessTracker

@Suite("StandaloneWorkoutRepository")
@MainActor
struct StandaloneWorkoutRepositoryTests {
    // MARK: - Fixtures

    private func makeSummary(id: String = "sw1", category: String = "Arms Only", order: Int = 1) -> StandaloneWorkoutSummaryDTO {
        StandaloneWorkoutSummaryDTO(
            id: id, category: category, order: order, name: nil, description: nil,
            createdAt: .now, count: StandaloneWorkoutSummaryDTO.Count(groups: 3)
        )
    }

    private func makeSession(id: String = "ss1", status: SessionStatus = .inProgress) -> StandaloneWorkoutSessionDTO {
        StandaloneWorkoutSessionDTO(
            id: id, userId: "u1", standaloneWorkoutId: "sw1",
            status: status, startedAt: .now,
            completedAt: status == .completed ? .now : nil, notes: nil
        )
    }

    private func makeCompletedSet(id: String = "cs1") -> StandaloneCompletedSetDTO {
        StandaloneCompletedSetDTO(
            id: id, standaloneWorkoutSessionId: "ss1",
            standaloneWorkoutSetId: "sws1", adhocExerciseName: nil,
            reps: 10, weight: 45, rpe: nil, notes: nil, completedAt: .now
        )
    }

    // MARK: - Catalog

    @Test("fetchCatalog decodes the raw array")
    func catalogFetch() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneWorkouts(category: nil), response: [makeSummary(), makeSummary(id: "sw2", order: 2)])
        let repo = StandaloneWorkoutRepository(apiClient: client)

        let catalog = try await repo.fetchCatalog()
        #expect(catalog.count == 2)
        #expect(catalog[0].id == "sw1")
    }

    // MARK: - Sessions

    @Test("startSession posts the workout id and unwraps the session")
    func startSession() async throws {
        let client = MockAPIClient()
        client.stub(
            .createStandaloneSession(CreateStandaloneSessionBody(standaloneWorkoutId: "sw1")),
            response: StandaloneSessionResponseDTO(session: makeSession())
        )
        let repo = StandaloneWorkoutRepository(apiClient: client)

        let session = try await repo.startSession(standaloneWorkoutId: "sw1")
        #expect(session.id == "ss1")
        #expect(session.status == .inProgress)
    }

    @Test("startSession surfaces the 409 for the resume flow")
    func startSessionConflict() async throws {
        let client = MockAPIClient()
        client.handlers["POST /api/standalone-workout-sessions"] = { _ in
            throw APIError.httpError(statusCode: 409, message: "A session for this workout is already in progress", data: Data())
        }
        let repo = StandaloneWorkoutRepository(apiClient: client)

        await #expect(throws: APIError.httpError(statusCode: 409, message: nil, data: Data())) {
            try await repo.startSession(standaloneWorkoutId: "sw1")
        }
    }

    // MARK: - Set logging

    @Test("recordSet sends the prescribed discriminator")
    func recordPrescribed() async throws {
        let client = MockAPIClient()
        client.stub(
            .recordStandaloneSet(
                sessionId: "ss1",
                body: .prescribed(standaloneWorkoutSetId: "sws1", reps: 10, weight: 45, rpe: nil, notes: nil)
            ),
            response: makeCompletedSet()
        )
        let repo = StandaloneWorkoutRepository(apiClient: client)

        let set = try await repo.recordSet(sessionId: "ss1", standaloneWorkoutSetId: "sws1", reps: 10, weight: 45, rpe: nil, notes: nil)
        #expect(set.id == "cs1")
    }

    @Test("updateSet patches by completed-set id")
    func updateSetDispatch() async throws {
        let client = MockAPIClient()
        let body = UpdateSetBody(reps: 12, weight: 50, rpe: nil, notes: nil)
        client.stub(.updateStandaloneSet(sessionId: "ss1", setId: "cs1", body: body), response: makeCompletedSet())
        let repo = StandaloneWorkoutRepository(apiClient: client)

        let set = try await repo.updateSet(sessionId: "ss1", setId: "cs1", body: body)
        #expect(set.id == "cs1")
    }

    @Test("deleteSet dispatches and ignores the response body")
    func deleteSetDispatch() async throws {
        let client = MockAPIClient()
        client.stub(.deleteStandaloneSet(sessionId: "ss1", setId: "cs1"), response: ["deleted": true])
        let repo = StandaloneWorkoutRepository(apiClient: client)

        try await repo.deleteSet(sessionId: "ss1", setId: "cs1")
    }

    // MARK: - Finalize / discard

    @Test("completeSession unwraps the completed session")
    func completeSession() async throws {
        let client = MockAPIClient()
        client.stub(
            .completeStandaloneSession(id: "ss1", body: nil),
            response: StandaloneSessionResponseDTO(session: makeSession(status: .completed))
        )
        let repo = StandaloneWorkoutRepository(apiClient: client)

        let session = try await repo.completeSession(id: "ss1")
        #expect(session.status == .completed)
        #expect(session.completedAt != nil)
    }

    @Test("abandonSession dispatches DELETE")
    func abandonSession() async throws {
        let client = MockAPIClient()
        client.stub(.abandonStandaloneSession(id: "ss1"), response: ["success": true])
        let repo = StandaloneWorkoutRepository(apiClient: client)

        try await repo.abandonSession(id: "ss1")
    }

    // MARK: - History

    @Test("fetchHistory passes the cursor pair together")
    func historyCursor() async throws {
        let client = MockAPIClient()
        let cursor = Date(timeIntervalSince1970: 1_700_000_000)
        client.handlers["GET /api/standalone-workout-sessions/history"] = { endpoint in
            guard case .getStandaloneSessionHistory(let limit, let before, let beforeId) = endpoint else {
                throw APIError.missingHandler(path: "unexpected endpoint")
            }
            #expect(limit == 20)
            #expect(before == cursor)
            #expect(beforeId == "ss9")
            return try JSONCoding.encoder.encode(StandaloneSessionListResponseDTO(sessions: []))
        }
        let repo = StandaloneWorkoutRepository(apiClient: client)

        let page = try await repo.fetchHistory(limit: 20, before: cursor, beforeId: "ss9")
        #expect(page.isEmpty)
    }
}
