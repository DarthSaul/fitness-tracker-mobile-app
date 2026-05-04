import Foundation
import Observation
import OSLog

/// Owns the active-workout state surfaced by the resume banner. Polls the
/// server lazily on appear; PR #7 will hook completion / abandon events to
/// trigger an explicit refresh.
@Observable
@MainActor
final class ResumeWorkoutViewModel {
    /// Nil when there's no in-progress session, or when the most recent fetch
    /// errored. The banner stays hidden in either case — this is a passive
    /// surface, not a place to surface API errors.
    private(set) var activeSession: ActiveWorkoutResponseDTO.ActiveWorkoutSession?

    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func refresh() async {
        do {
            let response: ActiveWorkoutResponseDTO = try await apiClient.send(.getActiveWorkout)
            activeSession = response.session
        } catch APIError.httpError(let statusCode, _) where statusCode == 404 {
            // Expected: no active session.
            activeSession = nil
        } catch {
            // Banner stays hidden on any other error — don't surface a
            // transient failure as a UI problem; the user can still navigate.
            Logger.networking.debug("ResumeWorkoutViewModel.refresh failed: \(error)")
            activeSession = nil
        }
    }

    func clear() {
        activeSession = nil
    }
}
