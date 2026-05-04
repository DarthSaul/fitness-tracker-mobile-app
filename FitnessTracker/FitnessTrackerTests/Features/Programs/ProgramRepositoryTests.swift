import Foundation
import Testing
import SwiftData
@testable import FitnessTracker

@Suite("ProgramRepository")
@MainActor
struct ProgramRepositoryTests {
    // MARK: - Fixtures
    private func makeRepository(apiClient: MockAPIClient) throws -> (ProgramRepository, ModelContext) {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let repo = ProgramRepository(apiClient: apiClient, modelContext: context)
        return (repo, context)
    }

    private func makeDTO(id: String = "p1", name: String = "Strength Base") -> ProgramDTO {
        ProgramDTO(id: id, name: name, description: "A solid strength program.", createdAt: .now)
    }

    // MARK: - Tests
    @Test("fetchPrograms upserts API response into SwiftData")
    func fetchProgramsUpserts() async throws {
        let client = MockAPIClient()
        client.stub(.getPrograms, response: [makeDTO()])

        let (repo, context) = try makeRepository(apiClient: client)
        let programs = try await repo.fetchPrograms()

        #expect(programs.count == 1)
        #expect(programs[0].id == "p1")
        #expect(programs[0].name == "Strength Base")

        let stored = try context.fetch(FetchDescriptor<ProgramModel>())
        #expect(stored.count == 1)
    }

    @Test("fetchPrograms updates existing record on second call")
    func fetchProgramsUpdatesExisting() async throws {
        let client = MockAPIClient()
        let (repo, context) = try makeRepository(apiClient: client)

        client.stub(.getPrograms, response: [makeDTO(name: "Original")])
        try await repo.fetchPrograms()

        client.stub(.getPrograms, response: [makeDTO(name: "Updated")])
        try await repo.fetchPrograms()

        let stored = try context.fetch(FetchDescriptor<ProgramModel>())
        #expect(stored.count == 1)
        #expect(stored[0].name == "Updated")
    }

    @Test("fetchPrograms propagates .unauthorized from API client")
    func fetchProgramsUnauthorized() async throws {
        let client = MockAPIClient()
        client.stubUnauthorized(for: "/api/programs")
        let (repo, _) = try makeRepository(apiClient: client)

        await #expect(throws: APIError.unauthorized) {
            try await repo.fetchPrograms()
        }
    }
}
