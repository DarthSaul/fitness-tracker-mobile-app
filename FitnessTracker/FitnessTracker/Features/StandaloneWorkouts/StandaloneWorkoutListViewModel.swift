import Foundation
import Observation
import OSLog

/// Drives the "Strength on the Go" browse screen: the standalone-workout
/// catalog grouped by category, plus the user's in-progress standalone
/// sessions so rows can badge "In progress" and offer resume.
@Observable
@MainActor
final class StandaloneWorkoutListViewModel {
    // MARK: - State
    private(set) var workouts: [StandaloneWorkoutSummaryDTO] = []
    private(set) var activeSessions: [StandaloneSessionListItemDTO] = []
    var isLoading = false
    private(set) var hasLoadedOnce = false
    var loadError: Error?

    // MARK: - Dependencies
    private let repository: StandaloneWorkoutRepository
    private let sessionManager: SessionManager

    init(repository: StandaloneWorkoutRepository, sessionManager: SessionManager) {
        self.repository = repository
        self.sessionManager = sessionManager
    }

    // MARK: - Derived

    /// Catalog grouped by category, preserving the server's ordering
    /// (category, then order) — no client-side re-sort.
    var groupedByCategory: [(category: String, workouts: [StandaloneWorkoutSummaryDTO])] {
        var result: [(category: String, workouts: [StandaloneWorkoutSummaryDTO])] = []
        for workout in workouts {
            if let lastIndex = result.indices.last, result[lastIndex].category == workout.category {
                result[lastIndex].workouts.append(workout)
            } else {
                result.append((category: workout.category, workouts: [workout]))
            }
        }
        return result
    }

    /// The in-progress session for a given workout, if any (server allows at
    /// most one per workout).
    func activeSession(forWorkoutId id: String) -> StandaloneSessionListItemDTO? {
        activeSessions.first { $0.standaloneWorkoutId == id }
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        loadError = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        do {
            async let catalogTask = repository.fetchCatalog()
            async let activeTask = repository.fetchActiveSessions()
            workouts = try await catalogTask
            // Active sessions only power the "In progress" badges — their
            // failure shouldn't blank the catalog.
            do {
                activeSessions = try await activeTask
            } catch {
                Logger.data.error("StandaloneWorkoutListViewModel active sessions failed: \(error)")
            }
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("StandaloneWorkoutListViewModel.load failed: \(error)")
            loadError = error
        }
    }

    /// Cheap re-check after the live-workout cover dismisses so badges track
    /// completes/abandons without refetching the whole catalog.
    func refreshActiveSessions() async {
        do {
            activeSessions = try await repository.fetchActiveSessions()
        } catch {
            Logger.data.error("StandaloneWorkoutListViewModel refreshActiveSessions failed: \(error)")
        }
    }
}
