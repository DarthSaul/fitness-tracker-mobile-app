import Foundation
import Observation
import OSLog

/// Drives the analytics dashboard. Mirrors the Vue `useAnalytics` composable:
/// dashboard + exercises load eagerly on `load()`; per-exercise history loads
/// imperatively when the user picks an exercise. Re-tapping a selected
/// exercise toggles it off. Stale-response handling matches the web's
/// AbortController pattern: each `selectExercise` increments
/// `historyRevision`, and any in-flight task whose revision no longer matches
/// the latest one drops its result on the floor.
@Observable
@MainActor
final class AnalyticsViewModel {
    // MARK: - State
    var dashboard: AnalyticsDashboardDTO?
    var exercises: [AnalyticsExerciseDTO] = []
    var selectedExerciseId: String?
    var exerciseHistory: AnalyticsExerciseHistoryDTO?

    var dashboardStatus: LoadStatus = .idle
    var exercisesStatus: LoadStatus = .idle
    var historyStatus: LoadStatus = .idle

    enum LoadStatus: Equatable {
        case idle
        case pending
        case success
        case error(String)
    }

    // MARK: - Dependencies
    private let repository: AnalyticsRepository
    private var historyTask: Task<Void, Never>?
    /// Bumped on every `selectExercise` call. The most recent revision wins.
    private var historyRevision = 0
    /// Bumped on every `load()` call. Concurrent `.task` + `.refreshable`
    /// invocations can interleave; only the latest token writes results back
    /// so an older slower response can't clobber a newer one.
    private var loadToken = 0

    init(repository: AnalyticsRepository) {
        self.repository = repository
    }

    // MARK: - Public API

    /// Loads dashboard and exercise list in parallel. Safe to call repeatedly
    /// (e.g. from `.refreshable`); each call refreshes both sources.
    func load() async {
        loadToken &+= 1
        let token = loadToken
        async let dash: Void = loadDashboard(token: token)
        async let ex: Void = loadExercises(token: token)
        _ = await (dash, ex)
    }

    func loadDashboard(token: Int) async {
        guard token == loadToken else { return }
        dashboardStatus = .pending
        do {
            let result = try await repository.fetchDashboard()
            guard token == loadToken else { return }
            self.dashboard = result
            self.dashboardStatus = .success
        } catch {
            if Self.isCancellation(error) { return }
            guard token == loadToken else { return }
            Logger.networking.error("Analytics dashboard failed: \(error.localizedDescription, privacy: .public)")
            self.dashboardStatus = .error(error.localizedDescription)
        }
    }

    func loadExercises(token: Int) async {
        guard token == loadToken else { return }
        exercisesStatus = .pending
        do {
            let result = try await repository.fetchExercises()
            guard token == loadToken else { return }
            self.exercises = result
            self.exercisesStatus = .success
        } catch {
            if Self.isCancellation(error) { return }
            guard token == loadToken else { return }
            Logger.networking.error("Analytics exercises failed: \(error.localizedDescription, privacy: .public)")
            self.exercisesStatus = .error(error.localizedDescription)
        }
    }

    /// True when `error` represents a cooperative cancellation rather than a
    /// real failure. Two surfaces matter for our networking pipeline:
    ///   - bare `CancellationError` (e.g. from `Task.sleep` or
    ///     `Task.checkCancellation`)
    ///   - `URLError.cancelled`, which is what `URLSession.data(for:)` throws
    ///     when its surrounding Task is cancelled. APIClient wraps that as
    ///     `APIError.network(URLError(.cancelled))`.
    /// Either way, the right behavior is to bail without logging or writing
    /// an .error status — the surrounding view is already on its way out.
    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if Task.isCancelled { return true }
        if let apiError = error as? APIError,
           case .network(let urlError) = apiError,
           urlError.code == .cancelled {
            return true
        }
        return false
    }

    /// Toggle-select an exercise. Tapping the same row clears the selection
    /// (matches web behavior where the selector's clear button + the chart
    /// reset converge on the same handler).
    func selectExercise(_ id: String) {
        if selectedExerciseId == id {
            clearSelection()
            return
        }

        historyTask?.cancel()
        historyRevision &+= 1
        let revision = historyRevision

        selectedExerciseId = id
        exerciseHistory = nil
        historyStatus = .pending

        historyTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await repository.fetchExerciseHistory(id: id)
                guard revision == self.historyRevision else { return }
                self.exerciseHistory = result
                self.historyStatus = .success
            } catch {
                guard revision == self.historyRevision else { return }
                if Task.isCancelled { return }
                Logger.networking.error("Analytics history failed: \(error.localizedDescription, privacy: .public)")
                self.historyStatus = .error(error.localizedDescription)
            }
        }
    }

    func clearSelection() {
        historyTask?.cancel()
        historyRevision &+= 1
        selectedExerciseId = nil
        exerciseHistory = nil
        historyStatus = .idle
    }
}
