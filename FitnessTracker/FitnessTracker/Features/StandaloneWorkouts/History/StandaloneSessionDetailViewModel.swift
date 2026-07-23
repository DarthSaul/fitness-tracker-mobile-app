import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class StandaloneSessionDetailViewModel {
    let sessionId: String

    var detail: StandaloneSessionDetailResponseDTO?
    var isLoading = false
    var loadError: Error?

    private let repository: StandaloneWorkoutRepository
    private let sessionManager: SessionManager

    init(sessionId: String, repository: StandaloneWorkoutRepository, sessionManager: SessionManager) {
        self.sessionId = sessionId
        self.repository = repository
        self.sessionManager = sessionManager
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            detail = try await repository.fetchSession(id: sessionId)
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("StandaloneSessionDetailViewModel.load failed: \(error)")
            loadError = error
        }
    }
}
