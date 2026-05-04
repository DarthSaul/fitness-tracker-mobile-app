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

    init(repository: AnalyticsRepository) {
        self.repository = repository
    }

    // MARK: - Public API

    /// Loads dashboard and exercise list in parallel. Safe to call repeatedly
    /// (e.g. from `.refreshable`); each call refreshes both sources.
    func load() async {
        async let dash: Void = loadDashboard()
        async let ex: Void = loadExercises()
        _ = await (dash, ex)
    }

    func loadDashboard() async {
        dashboardStatus = .pending
        do {
            self.dashboard = try await repository.fetchDashboard()
            self.dashboardStatus = .success
        } catch {
            Logger.networking.error("Analytics dashboard failed: \(error.localizedDescription, privacy: .public)")
            self.dashboardStatus = .error(error.localizedDescription)
        }
    }

    func loadExercises() async {
        exercisesStatus = .pending
        do {
            self.exercises = try await repository.fetchExercises()
            self.exercisesStatus = .success
        } catch {
            Logger.networking.error("Analytics exercises failed: \(error.localizedDescription, privacy: .public)")
            self.exercisesStatus = .error(error.localizedDescription)
        }
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
