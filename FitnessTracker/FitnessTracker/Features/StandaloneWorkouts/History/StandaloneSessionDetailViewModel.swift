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

    init(sessionId: String, repository: StandaloneWorkoutRepository) {
        self.sessionId = sessionId
        self.repository = repository
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            detail = try await repository.fetchSession(id: sessionId)
        } catch {
            Logger.data.error("StandaloneSessionDetailViewModel.load failed: \(error)")
            loadError = error
        }
    }
}
