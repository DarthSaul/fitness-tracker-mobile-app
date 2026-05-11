import Foundation
import Testing
@testable import FitnessTracker

@Suite("HistoryRepository")
@MainActor
struct HistoryRepositoryTests {
    private func makeSession(
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

    @Test("fetchHistory unwraps the sessions wrapper")
    func unwrapsSessions() async throws {
        let client = MockAPIClient()
        client.stub(
            .getWorkoutHistory(limit: nil, before: nil),
            response: WorkoutHistoryResponseDTO(sessions: [makeSession()])
        )
        let repo = HistoryRepository(apiClient: client)

        let result = try await repo.fetchHistory()
        #expect(result.count == 1)
        #expect(result[0].id == "ws1")
        #expect(result[0].programName == "Strength Base")
        #expect(result[0].count.completedSets == 7)
    }

    @Test("fetchHistory passes limit + before through to the endpoint URL")
    func appendsQueryItems() async throws {
        let client = MockAPIClient()
        let cursor = Date(timeIntervalSince1970: 1_700_500_000)
        var seenEndpoint: APIEndpoint?
        client.handlers["/api/workouts/history"] = { endpoint in
            seenEndpoint = endpoint
            return try JSONCoding.encoder.encode(WorkoutHistoryResponseDTO(sessions: []))
        }
        let repo = HistoryRepository(apiClient: client)

        _ = try await repo.fetchHistory(limit: 25, before: cursor)

        guard case .getWorkoutHistory(let limit, let before) = seenEndpoint else {
            Issue.record("Expected getWorkoutHistory endpoint")
            return
        }
        #expect(limit == 25)
        #expect(before == cursor)

        let items = seenEndpoint!.queryItems ?? []
        let names = items.map(\.name)
        #expect(names.contains("limit"))
        #expect(names.contains("before"))
        #expect(items.first(where: { $0.name == "limit" })?.value == "25")
    }

    @Test("fetchHistory with both params nil produces no query items")
    func noQueryItemsWhenAllNil() async throws {
        let endpoint = APIEndpoint.getWorkoutHistory(limit: nil, before: nil)
        #expect(endpoint.queryItems == nil)
    }

    @Test("HistorySessionDTO decodes the server's _count → count mapping")
    func decodesCountKey() throws {
        let json = """
        {
          "id": "ws1",
          "userId": "u1",
          "userProgramId": "up1",
          "programName": "Strength Base",
          "weekNumber": 2,
          "dayNumber": 3,
          "status": "COMPLETED",
          "startedAt": "2026-05-01T00:00:00.000Z",
          "completedAt": "2026-05-01T01:00:00.000Z",
          "notes": null,
          "_count": { "completedSets": 12 }
        }
        """.data(using: .utf8)!

        let dto = try JSONCoding.decoder.decode(HistorySessionDTO.self, from: json)
        #expect(dto.count.completedSets == 12)
        #expect(dto.status == .completed)
        #expect(dto.programName == "Strength Base")
    }
}
