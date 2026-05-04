import Foundation
import Testing
@testable import FitnessTracker

@Suite("UserProgramRepository")
@MainActor
struct UserProgramRepositoryTests {
    // MARK: - Fixtures
    private func makeUserProgramDTO(
        id: String = "up1",
        programId: String = "p1",
        isActive: Bool = false
    ) -> UserProgramWithProgramDTO {
        UserProgramWithProgramDTO(
            id: id,
            userId: "u1",
            programId: programId,
            isActive: isActive,
            currentWeek: 1,
            currentDay: 1,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            program: UserProgramWithProgramDTO.NestedProgram(
                id: programId,
                name: "Strength Base",
                description: nil
            )
        )
    }

    // Mutation endpoints (save/unsave/activate/deactivate) hit endpoints whose
    // responses we discard. Stub with a small JSON dummy so MockAPIClient
    // returns *some* Data — content doesn't matter to the void send overload.
    private let voidStub: [String: Bool] = ["ok": true]

    // MARK: - Fetch

    @Test("fetchUserPrograms decodes the array response")
    func fetchUserPrograms() async throws {
        let client = MockAPIClient()
        client.stub(.getUserPrograms, response: [makeUserProgramDTO(isActive: true)])
        let repo = UserProgramRepository(apiClient: client)

        let dtos = try await repo.fetchUserPrograms()

        #expect(dtos.count == 1)
        #expect(dtos[0].id == "up1")
        #expect(dtos[0].isActive == true)
        #expect(dtos[0].program.name == "Strength Base")
    }

    @Test("fetchUserPrograms propagates .unauthorized")
    func fetchUserProgramsUnauthorized() async throws {
        let client = MockAPIClient()
        client.stubUnauthorized(for: .getUserPrograms)
        let repo = UserProgramRepository(apiClient: client)

        await #expect(throws: APIError.unauthorized) {
            try await repo.fetchUserPrograms()
        }
    }

    // MARK: - Save / Unsave

    @Test("saveProgram dispatches POST /api/user-programs")
    func saveProgramHitsEndpoint() async throws {
        let client = MockAPIClient()
        client.stub(.saveProgram(programId: "p1"), response: voidStub)
        let repo = UserProgramRepository(apiClient: client)

        try await repo.saveProgram(programId: "p1")
        // No throw → endpoint resolved (MockAPIClient throws .missingHandler otherwise).
    }

    @Test("unsaveProgram dispatches DELETE /api/user-programs/:id")
    func unsaveProgramHitsEndpoint() async throws {
        let client = MockAPIClient()
        client.stub(.unsaveProgram(userProgramId: "up1"), response: voidStub)
        let repo = UserProgramRepository(apiClient: client)

        try await repo.unsaveProgram(userProgramId: "up1")
    }

    // MARK: - Activate / Deactivate

    @Test("activateProgram dispatches PATCH /api/user-programs/:id/activate")
    func activateProgramHitsEndpoint() async throws {
        let client = MockAPIClient()
        client.stub(.activateProgram(userProgramId: "up1"), response: voidStub)
        let repo = UserProgramRepository(apiClient: client)

        try await repo.activateProgram(userProgramId: "up1")
    }

    @Test("deactivateProgram dispatches PATCH /api/user-programs/:id/deactivate")
    func deactivateProgramHitsEndpoint() async throws {
        let client = MockAPIClient()
        client.stub(.deactivateProgram(userProgramId: "up1"), response: voidStub)
        let repo = UserProgramRepository(apiClient: client)

        try await repo.deactivateProgram(userProgramId: "up1")
    }

    @Test("activateProgram propagates .unauthorized")
    func activateProgramUnauthorized() async throws {
        let client = MockAPIClient()
        client.stubUnauthorized(for: .activateProgram(userProgramId: "up1"))
        let repo = UserProgramRepository(apiClient: client)

        await #expect(throws: APIError.unauthorized) {
            try await repo.activateProgram(userProgramId: "up1")
        }
    }
}
