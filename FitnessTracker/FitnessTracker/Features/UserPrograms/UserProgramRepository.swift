import Foundation
import OSLog

@MainActor
final class UserProgramRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - Fetch
    func fetchUserPrograms() async throws -> [UserProgramWithProgramDTO] {
        let dtos: [UserProgramWithProgramDTO] = try await apiClient.send(.getUserPrograms)
        Logger.data.info("Fetched \(dtos.count) saved user-programs.")
        return dtos
    }

    // MARK: - Save / Unsave
    // The mutation responses (save / activate / deactivate) carry the updated
    // UserProgram, but we discard them and re-fetch the full list afterwards
    // so client state can never disagree with the server (mirrors the web
    // composable's `await refresh()` pattern).
    func saveProgram(programId: String) async throws {
        try await apiClient.send(.saveProgram(programId: programId))
    }

    func unsaveProgram(userProgramId: String) async throws {
        try await apiClient.send(.unsaveProgram(userProgramId: userProgramId))
    }

    // MARK: - Activate / Deactivate
    func activateProgram(userProgramId: String) async throws {
        try await apiClient.send(.activateProgram(userProgramId: userProgramId))
    }

    func deactivateProgram(userProgramId: String) async throws {
        try await apiClient.send(.deactivateProgram(userProgramId: userProgramId))
    }
}
