import Foundation
import Observation
import OSLog

/// Owns the active-workout state surfaced by the resume banner. Polls the
/// server lazily on appear and re-checks whenever the live-workout cover
/// dismisses. Covers both flavors of in-progress session: the program workout
/// (at most one, via /api/workouts/active) and standalone sessions (newest
/// first, via /api/standalone-workout-sessions/active). The app-level rule is
/// one active workout at a time across both, so the banner shows whichever
/// exists — program wins if the rule was somehow violated (e.g. via the web).
@Observable
@MainActor
final class ResumeWorkoutViewModel {
    enum ActiveWorkout {
        case program(ActiveWorkoutResponseDTO.ActiveWorkoutSession)
        case standalone(StandaloneSessionListItemDTO)
    }

    /// Nil when there's no in-progress session, or when the most recent fetch
    /// errored. The banner stays hidden in either case — this is a passive
    /// surface, not a place to surface API errors.
    private(set) var activeWorkout: ActiveWorkout?

    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func refresh() async {
        do {
            let response: ActiveWorkoutResponseDTO = try await apiClient.send(.getActiveWorkout)
            activeWorkout = .program(response.session)
            return
        } catch APIError.httpError(let statusCode, _, _) where statusCode == 404 {
            // Expected: no active program session — fall through to standalone.
        } catch {
            // Banner stays hidden on any other error — don't surface a
            // transient failure as a UI problem; the user can still navigate.
            Logger.networking.debug("ResumeWorkoutViewModel program refresh failed: \(error)")
            activeWorkout = nil
            return
        }

        do {
            let response: StandaloneSessionListResponseDTO = try await apiClient.send(.getActiveStandaloneSessions)
            activeWorkout = response.sessions.first.map { .standalone($0) }
        } catch {
            Logger.networking.debug("ResumeWorkoutViewModel standalone refresh failed: \(error)")
            activeWorkout = nil
        }
    }

    func clear() {
        activeWorkout = nil
    }
}
