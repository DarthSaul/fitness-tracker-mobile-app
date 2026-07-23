import Foundation
import Testing
@testable import FitnessTracker

@Suite("HistoryRepository")
@MainActor
struct HistoryRepositoryTests {
    private func makeProgramSession(
        id: String = "ws1",
        programName: String = "Strength Base",
        completedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> HistorySessionDTO {
        HistorySessionDTO(
            id: id, userId: "u1", userProgramId: "up1",
            programName: programName,
            weekNumber: 1, dayNumber: 1, status: .completed,
            startedAt: completedAt, completedAt: completedAt, notes: nil,
            count: HistorySessionDTO.Count(completedSets: 7)
        )
    }

    private func makeStandaloneSession(
        id: String = "ss1",
        completedAt: Date = Date(timeIntervalSince1970: 1_699_990_000)
    ) -> StandaloneSessionListItemDTO {
        StandaloneSessionListItemDTO(
            id: id, userId: "u1", standaloneWorkoutId: "sw1",
            status: .completed, startedAt: completedAt, completedAt: completedAt, notes: nil,
            count: StandaloneSessionListItemDTO.Count(completedSets: 4),
            standaloneWorkout: StandaloneSessionListItemDTO.WorkoutRef(
                id: "sw1", category: "Arms Only", order: 2, name: nil
            )
        )
    }

    @Test("fetchHistory unwraps mixed program and standalone rows in order")
    func unwrapsMixedSessions() async throws {
        let client = MockAPIClient()
        client.stub(
            .getHistory(type: nil, limit: nil, before: nil, beforeId: nil),
            response: HistoryResponseDTO(sessions: [
                .program(makeProgramSession()),
                .standalone(makeStandaloneSession())
            ])
        )
        let repo = HistoryRepository(apiClient: client)

        let result = try await repo.fetchHistory()
        #expect(result.count == 2)
        guard case .program(let program) = result[0] else {
            Issue.record("Expected a program row first")
            return
        }
        #expect(program.programName == "Strength Base")
        #expect(program.count.completedSets == 7)
        guard case .standalone(let standalone) = result[1] else {
            Issue.record("Expected a standalone row second")
            return
        }
        #expect(standalone.standaloneWorkout.displayName == "Arms Only #2")
    }

    @Test("fetchHistory passes type + limit + cursor pair through to the endpoint URL")
    func appendsQueryItems() async throws {
        let client = MockAPIClient()
        let cursor = Date(timeIntervalSince1970: 1_700_500_000)
        var seenEndpoint: APIEndpoint?
        client.handlers["GET /api/history"] = { endpoint in
            seenEndpoint = endpoint
            return try JSONCoding.encoder.encode(HistoryResponseDTO(sessions: []))
        }
        let repo = HistoryRepository(apiClient: client)

        _ = try await repo.fetchHistory(type: .standalone, limit: 25, before: cursor, beforeId: "ws9")

        guard case .getHistory(let type, let limit, let before, let beforeId) = seenEndpoint else {
            Issue.record("Expected getHistory endpoint")
            return
        }
        #expect(type == .standalone)
        #expect(limit == 25)
        #expect(before == cursor)
        #expect(beforeId == "ws9")

        let items = seenEndpoint!.queryItems ?? []
        let names = items.map(\.name)
        #expect(names.contains("type"))
        #expect(names.contains("limit"))
        #expect(names.contains("before"))
        #expect(names.contains("beforeId"))
        #expect(items.first(where: { $0.name == "type" })?.value == "standalone")
        #expect(items.first(where: { $0.name == "limit" })?.value == "25")
        #expect(items.first(where: { $0.name == "beforeId" })?.value == "ws9")
    }

    @Test("fetchHistory with all params nil produces no query items")
    func noQueryItemsWhenAllNil() async throws {
        let endpoint = APIEndpoint.getHistory(type: nil, limit: nil, before: nil, beforeId: nil)
        #expect(endpoint.queryItems == nil)
    }

    // MARK: - Unified row decoding

    @Test("HistoryResponseDTO decodes both row types from the wire shape")
    func decodesBothRowTypes() throws {
        let json = """
        { "sessions": [
          { "type": "PROGRAM",
            "id": "ws1", "userId": "u1", "userProgramId": "up1",
            "programName": "Strength Base", "weekNumber": 2, "dayNumber": 3,
            "status": "COMPLETED",
            "startedAt": "2026-05-01T00:00:00.000Z",
            "completedAt": "2026-05-01T01:00:00.000Z",
            "notes": null,
            "_count": { "completedSets": 12 } },
          { "type": "STANDALONE",
            "id": "ss1", "userId": "u1", "standaloneWorkoutId": "sw1",
            "standaloneWorkout": { "id": "sw1", "category": "KB Only", "order": 3, "name": null },
            "status": "COMPLETED",
            "startedAt": "2026-04-30T00:00:00.000Z",
            "completedAt": "2026-04-30T01:00:00.000Z",
            "notes": null,
            "_count": { "completedSets": 6 } }
        ] }
        """.data(using: .utf8)!

        let response = try JSONCoding.decoder.decode(HistoryResponseDTO.self, from: json)

        #expect(response.sessions.count == 2)
        guard case .program(let program) = response.sessions[0] else {
            Issue.record("Expected a program row")
            return
        }
        #expect(program.count.completedSets == 12)
        #expect(program.weekNumber == 2)
        guard case .standalone(let standalone) = response.sessions[1] else {
            Issue.record("Expected a standalone row")
            return
        }
        #expect(standalone.standaloneWorkout.displayName == "KB Only #3")
        #expect(standalone.count.completedSets == 6)
    }

    @Test("rows with an unknown type are dropped, not a page-wide failure")
    func unknownTypeTolerated() throws {
        let json = """
        { "sessions": [
          { "type": "PROGRAM",
            "id": "ws1", "userId": "u1", "userProgramId": "up1",
            "programName": "Strength Base", "weekNumber": 1, "dayNumber": 1,
            "status": "COMPLETED",
            "startedAt": "2026-05-01T00:00:00.000Z",
            "completedAt": "2026-05-01T01:00:00.000Z",
            "notes": null,
            "_count": { "completedSets": 5 } },
          { "type": "MOBILITY_FLOW", "id": "mf1", "someFutureField": true }
        ] }
        """.data(using: .utf8)!

        let response = try JSONCoding.decoder.decode(HistoryResponseDTO.self, from: json)

        #expect(response.sessions.count == 1)
        #expect(response.sessions[0].id == "ws1")
    }

    @Test("HistoryEntryDTO round-trips through the encoder with the type key")
    func entryEncodesTypeKey() throws {
        let entry = HistoryEntryDTO.standalone(makeStandaloneSession())
        let data = try JSONCoding.encoder.encode(entry)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "STANDALONE")
        #expect(object["standaloneWorkoutId"] as? String == "sw1")

        let decoded = try JSONCoding.decoder.decode(HistoryEntryDTO.self, from: data)
        #expect(decoded == entry)
    }
}
