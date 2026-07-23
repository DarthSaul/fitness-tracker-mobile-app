import Foundation
import Observation
import OSLog

/// Drives the standalone-workout detail screen: the full template preview and
/// the Start/Resume CTA, including the one-active-workout-at-a-time rule.
///
/// The app enforces a single in-progress workout across BOTH flavors (program
/// and standalone) even though the server allows one standalone session per
/// workout. Starting here while anything else is in progress sets `blocker`
/// instead — the view prompts the user to complete or discard it first.
@Observable
@MainActor
final class StandaloneWorkoutDetailViewModel {
    /// The in-progress workout preventing a start, surfaced as an alert with
    /// complete / discard / cancel choices.
    enum Blocker {
        case program(ActiveWorkoutResponseDTO.ActiveWorkoutSession)
        case standalone(StandaloneSessionListItemDTO)

        /// Human name for the alert copy.
        var workoutName: String {
            switch self {
            case .program(let session):
                return "Week \(session.weekNumber) · Day \(session.dayNumber) of your program"
            case .standalone(let session):
                return session.standaloneWorkout.displayName
            }
        }
    }

    // MARK: - State
    let workoutId: String
    var workout: StandaloneWorkoutDetailDTO?
    var isLoading = false
    var loadError: Error?
    var isStarting = false
    var actionError: String?
    /// In-progress session for THIS workout → the CTA flips to "Resume workout".
    private(set) var activeSessionForThisWorkout: StandaloneSessionListItemDTO?
    /// Non-nil when a start attempt was blocked by another in-progress workout.
    var blocker: Blocker?

    // MARK: - Dependencies
    private let repository: StandaloneWorkoutRepository
    private let workoutRepository: WorkoutRepository
    private let sessionManager: SessionManager
    private let markedCompleteStore: MarkedCompleteStore

    init(
        workoutId: String,
        repository: StandaloneWorkoutRepository,
        workoutRepository: WorkoutRepository,
        sessionManager: SessionManager,
        markedCompleteStore: MarkedCompleteStore = MarkedCompleteStore()
    ) {
        self.workoutId = workoutId
        self.repository = repository
        self.workoutRepository = workoutRepository
        self.sessionManager = sessionManager
        self.markedCompleteStore = markedCompleteStore
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let workoutTask = repository.fetchWorkout(id: workoutId)
            async let activeTask = repository.fetchActiveSessions()
            workout = try await workoutTask
            // Resume state is secondary — its failure shouldn't blank the template.
            do {
                let actives = try await activeTask
                activeSessionForThisWorkout = actives.first { $0.standaloneWorkoutId == workoutId }
            } catch {
                Logger.data.error("StandaloneWorkoutDetail active sessions failed: \(error)")
            }
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("StandaloneWorkoutDetailViewModel.load failed: \(error)")
            loadError = error
        }
    }

    /// Re-check after the live cover dismisses — the session may have been
    /// completed or abandoned, which flips the CTA back to "Start workout".
    func refreshActiveSession() async {
        do {
            let actives = try await repository.fetchActiveSessions()
            activeSessionForThisWorkout = actives.first { $0.standaloneWorkoutId == workoutId }
        } catch {
            Logger.data.error("StandaloneWorkoutDetail refreshActiveSession failed: \(error)")
        }
    }

    // MARK: - Start / resume

    /// CTA tap. Returns the session id to present, or nil when blocked (the
    /// view shows the blocker alert) or on error (`actionError` set).
    func startOrResume() async -> String? {
        guard !isStarting else { return nil }
        if let existing = activeSessionForThisWorkout { return existing.id }

        isStarting = true
        actionError = nil
        blocker = nil
        defer { isStarting = false }
        do {
            // One active workout at a time, across program and standalone.
            if let program = try await workoutRepository.getActiveWorkout() {
                blocker = .program(program.session)
                return nil
            }
            let actives = try await repository.fetchActiveSessions()
            if let mine = actives.first(where: { $0.standaloneWorkoutId == workoutId }) {
                activeSessionForThisWorkout = mine
                return mine.id
            }
            if let other = actives.first {
                blocker = .standalone(other)
                return nil
            }
            return try await start()
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return nil
        } catch {
            Logger.data.error("startOrResume failed: \(error)")
            actionError = error.localizedDescription
            return nil
        }
    }

    /// Resolves the blocking workout per the user's alert choice (complete or
    /// discard), then starts this one. Returns the session id to present.
    /// The blocker is passed in (captured by the alert button before SwiftUI's
    /// dismissal clears the published `blocker` state).
    func resolveBlockerAndStart(_ blocker: Blocker, discard: Bool) async -> String? {
        guard !isStarting else { return nil }
        isStarting = true
        actionError = nil
        do {
            switch blocker {
            case .program(let session):
                if discard {
                    try await workoutRepository.abandonWorkout(id: session.id)
                } else {
                    _ = try await workoutRepository.completeWorkout(id: session.id, completedAt: nil)
                }
                markedCompleteStore.clear(sessionId: session.id)
            case .standalone(let session):
                if discard {
                    try await repository.abandonSession(id: session.id)
                } else {
                    _ = try await repository.completeSession(id: session.id)
                }
                markedCompleteStore.clear(sessionId: session.id)
            }
            self.blocker = nil
            isStarting = false
            return await startOrResume()
        } catch let apiError as APIError where apiError == .unauthorized {
            isStarting = false
            await sessionManager.signOut()
            return nil
        } catch {
            isStarting = false
            Logger.data.error("resolveBlockerAndStart failed: \(error)")
            actionError = error.localizedDescription
            return nil
        }
    }

    /// POST the new session. A 409 means a session for this workout is already
    /// in progress (raced with another device/tab) — fetch it and resume
    /// instead of surfacing an error.
    private func start() async throws -> String? {
        do {
            let session = try await repository.startSession(standaloneWorkoutId: workoutId)
            return session.id
        } catch APIError.httpError(let statusCode, _, _) where statusCode == 409 {
            let actives = try await repository.fetchActiveSessions()
            if let mine = actives.first(where: { $0.standaloneWorkoutId == workoutId }) {
                activeSessionForThisWorkout = mine
                return mine.id
            }
            actionError = "This workout is already in progress."
            return nil
        }
    }
}
