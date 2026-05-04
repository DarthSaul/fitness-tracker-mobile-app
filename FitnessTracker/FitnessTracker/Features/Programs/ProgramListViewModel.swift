import Foundation
import Observation
import OSLog

@Observable
final class ProgramListViewModel {
    // MARK: - State
    var programs: [ProgramModel] = []
    var isLoading = false
    var error: Error?

    // MARK: - Dependencies
    private let repository: ProgramRepository
    private let sessionManager: SessionManager

    init(repository: ProgramRepository, sessionManager: SessionManager) {
        self.repository = repository
        self.sessionManager = sessionManager
    }

    // MARK: - Actions
    @MainActor
    func loadPrograms() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            programs = try await repository.fetchPrograms()
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("Failed to load programs: \(error)")
            // Attempt to show cached data on network failure
            programs = (try? repository.cachedPrograms()) ?? []
            self.error = error
        }
    }
}

