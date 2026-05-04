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

    var selectedDate: Date = HomeViewModel.startOfDay(.now)
    var isLoading = false
    var loadError: Error?
    var scheduleError: String?
    var isStartingWorkout = false
    var isUnscheduling = false

    // MARK: - Dependencies
    private let repository: HomeRepository
    private let sessionManager: SessionManager
    private let calendar: Calendar

    init(
        repository: HomeRepository,
        sessionManager: SessionManager,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.sessionManager = sessionManager
        self.calendar = calendar
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

    /// First three exercise names from the next workout day, used in the today card preview.
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
        defer { isLoading = false }

        do {
            async let activeProgramTask = repository.fetchActiveUserProgram()
            async let activeWorkoutTask = repository.fetchActiveWorkout()
            async let sessionsTask = repository.fetchActiveProgramSessions()
            let (program, workout, sessions) = try await (activeProgramTask, activeWorkoutTask, sessionsTask)
            self.activeProgram = program
            self.activeWorkout = workout
            self.sessions = sessions

            // Scheduled workouts depend on having an active program — fetch in a
            // second pass once we know the userProgramId.
            if let userProgramId = program?.id {
                self.scheduledWorkouts = (try? await repository.fetchScheduledWorkouts(userProgramId: userProgramId)) ?? []
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
