import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class HomeViewModel {
    // MARK: - State
    var activeProgram: ActiveUserProgramDTO?
    var activeWorkout: ActiveWorkoutResponseDTO?
    var sessions: [ActiveProgramSessionDTO] = []
    var scheduledWorkouts: [ScheduledWorkoutDTO] = []
    /// 5 most-recent completed sessions across all programs, surfaced in the
    /// Home page "History" preview list.
    var recentHistory: [HistorySessionDTO] = []

    var selectedDate: Date = HomeViewModel.startOfDay(.now)
    var isLoading = false
    /// True once `load()` has completed at least once (success or failure).
    /// Used to suppress the "No active program" empty state during the first
    /// fetch — otherwise it briefly flashes on sign-in before data arrives.
    private(set) var hasLoadedOnce = false
    var loadError: Error?
    var scheduleError: String?
    var isStartingWorkout = false
    var isUnscheduling = false

    // MARK: - Dependencies
    private let repository: HomeRepository
    private let historyRepository: HistoryRepository
    private let sessionManager: SessionManager
    private let calendar: Calendar
    private let recentHistoryLimit: Int

    init(
        repository: HomeRepository,
        historyRepository: HistoryRepository,
        sessionManager: SessionManager,
        calendar: Calendar = .current,
        recentHistoryLimit: Int = 5
    ) {
        self.repository = repository
        self.historyRepository = historyRepository
        self.sessionManager = sessionManager
        self.calendar = calendar
        self.recentHistoryLimit = recentHistoryLimit
    }

    // MARK: - Derived state

    var hasActiveProgram: Bool { activeProgram != nil }

    var hasActiveWorkout: Bool { activeWorkout != nil }

    var totalDays: Int {
        guard let activeProgram else { return 0 }
        return activeProgram.program.weeks.reduce(0) { $0 + $1.days.count }
    }

    var completedDays: Int {
        sessions.filter { $0.status == .completed }.count
    }

    /// Integer percentage clamped to 0...100. Returns 0 when the program has no days.
    var progressPercent: Int {
        guard totalDays > 0 else { return 0 }
        return min(100, max(0, Int((Double(completedDays) / Double(totalDays) * 100).rounded())))
    }

    /// The ProgramDay the user is currently on, lifted out of the active program tree.
    var nextWorkoutDay: ProgramDayWithExercises? {
        guard let activeProgram else { return nil }
        let week = activeProgram.program.weeks.first { $0.weekNumber == activeProgram.currentWeek }
        return week?.days.first { $0.dayNumber == activeProgram.currentDay }
    }

    /// All exercise names from the next workout day. The Today card slices the
    /// first three for its preview list and uses the full count to render
    /// "+N more" — keep returning the full list rather than pre-slicing here.
    var nextWorkoutExerciseNames: [String] {
        guard let day = nextWorkoutDay else { return [] }
        return day.exerciseGroups.flatMap { $0.exercises.map { $0.exercise.name } }
    }

    var isViewingToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: .now)
    }

    /// Schedule (if any) for the selected non-today date.
    var scheduledForSelectedDate: ScheduledWorkoutDTO? {
        scheduledWorkouts.first { calendar.isDate($0.scheduledDate, inSameDayAs: selectedDate) }
    }

    /// Returns the schedule (if any) for a given week/day in the active program.
    func schedule(forWeek weekNumber: Int, day dayNumber: Int) -> ScheduledWorkoutDTO? {
        scheduledWorkouts.first { $0.weekNumber == weekNumber && $0.dayNumber == dayNumber }
    }

    /// Day-string keys ("yyyy-MM-dd") used by the calendar strip to mark dates that have schedules.
    var scheduledDateKeys: Set<String> {
        Set(scheduledWorkouts.map { Self.dayKey($0.scheduledDate, calendar: calendar) })
    }

    /// Day name from the active program tree, when present.
    func dayName(forWeek weekNumber: Int, day dayNumber: Int) -> String? {
        guard let activeProgram else { return nil }
        let week = activeProgram.program.weeks.first { $0.weekNumber == weekNumber }
        return week?.days.first { $0.dayNumber == dayNumber }?.name
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
            async let activeProgramTask = repository.fetchActiveUserProgram()
            async let activeWorkoutTask = repository.fetchActiveWorkout()
            async let sessionsTask = repository.fetchActiveProgramSessions()
            // Kicked off in parallel but awaited below — recent history is a
            // Home preview, not part of the critical dashboard, so its failure
            // shouldn't blank out the rest of the page.
            async let recentHistoryTask = historyRepository.fetchHistory(limit: recentHistoryLimit, before: nil)
            let (program, workout, sessions) = try await (activeProgramTask, activeWorkoutTask, sessionsTask)
            self.activeProgram = program
            self.activeWorkout = workout
            self.sessions = sessions

            do {
                self.recentHistory = try await recentHistoryTask
            } catch {
                Logger.data.error("Failed to fetch recent history: \(error)")
            }

            // Scheduled workouts depend on having an active program — fetch in a
            // second pass once we know the userProgramId.
            if let userProgramId = program?.id {
                do {
                    self.scheduledWorkouts = try await repository.fetchScheduledWorkouts(userProgramId: userProgramId)
                } catch let apiError as APIError where apiError == .unauthorized {
                    await sessionManager.signOut()
                    return
                } catch {
                    // Surface the failure to the user but keep the rest of the
                    // dashboard usable — the active program / workout / sessions
                    // we just loaded are still valid; only the schedule list is missing.
                    Logger.data.error("Failed to fetch scheduled workouts: \(error)")
                    self.scheduledWorkouts = []
                    self.loadError = error
                }
            } else {
                self.scheduledWorkouts = []
            }
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("HomeViewModel.load failed: \(error)")
            self.loadError = error
        }
    }

    // MARK: - Schedule / Unschedule

    func schedule(weekNumber: Int, dayNumber: Int) async {
        guard let userProgramId = activeProgram?.id else { return }
        scheduleError = nil
        do {
            _ = try await repository.scheduleWorkout(
                userProgramId: userProgramId,
                weekNumber: weekNumber,
                dayNumber: dayNumber,
                scheduledDate: selectedDate
            )
            await refreshScheduled()
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("schedule failed: \(error)")
            scheduleError = error.localizedDescription
        }
    }

    func unscheduleSelected() async {
        guard let scheduled = scheduledForSelectedDate, !isUnscheduling else { return }
        isUnscheduling = true
        scheduleError = nil
        defer { isUnscheduling = false }
        do {
            try await repository.unscheduleWorkout(id: scheduled.id)
            await refreshScheduled()
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("unschedule failed: \(error)")
            scheduleError = error.localizedDescription
        }
    }

    /// Starts the next workout in the active program. Returns the new session id, or nil on failure.
    /// PR #7 wires up navigation to the live workout view from the returned id.
    func startNextWorkout() async -> String? {
        guard !isStartingWorkout else { return nil }
        isStartingWorkout = true
        defer { isStartingWorkout = false }
        do {
            let response = try await repository.startWorkout()
            // Optimistically reflect the new active workout so the UI flips state immediately.
            self.activeWorkout = nil  // Will be repopulated by the next load.
            await load()
            return response.session.id
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return nil
        } catch {
            Logger.data.error("startNextWorkout failed: \(error)")
            scheduleError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Helpers

    private func refreshScheduled() async {
        guard let userProgramId = activeProgram?.id else { return }
        do {
            scheduledWorkouts = try await repository.fetchScheduledWorkouts(userProgramId: userProgramId)
        } catch {
            Logger.data.error("Failed to refresh scheduled workouts: \(error)")
        }
    }

    private static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// "yyyy-MM-dd" key in the given calendar's time zone. Built from components
    /// rather than a shared DateFormatter so calls from any actor are safe.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Convenience alias for the deeply-nested ProgramDay shape inside ActiveUserProgramDTO.
typealias ProgramDayWithExercises = ProgramDayDTO
