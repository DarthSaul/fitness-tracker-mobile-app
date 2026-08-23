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
    /// In-progress standalone sessions. The app allows one active workout at a
    /// time across program and standalone, so a non-empty list blocks "Start
    /// next workout" until the user completes or discards it.
    var activeStandaloneSessions: [StandaloneSessionListItemDTO] = []
    /// Completed sessions — program and standalone interleaved, newest first —
    /// accumulated by paging the unified GET /api/history back to the calendar
    /// strip's window. Drives the calendar's completed-day highlights, the
    /// selected-day completed cards, and the Home "History" preview.
    var history: [HistoryEntryDTO] = []

    var selectedDate: Date = HomeViewModel.startOfDay(.now)
    var isLoading = false
    /// True once `load()` has completed at least once (success or failure).
    /// Used to suppress the "No active program" empty state during the first
    /// fetch — otherwise it briefly flashes on sign-in before data arrives.
    private(set) var hasLoadedOnce = false
    var loadError: Error?
    var scheduleError: String?
    /// Failure surfaced on the Today card when completing/discarding a
    /// blocking standalone session ahead of a program start.
    var startConflictError: String?
    var isStartingWorkout = false
    var isUnscheduling = false

    // MARK: - Dependencies
    private let repository: HomeRepository
    private let historyRepository: HistoryRepository
    private let standaloneRepository: StandaloneWorkoutRepository
    private let sessionManager: SessionManager
    private let calendar: Calendar
    private let recentHistoryLimit: Int
    private let historyPageSize: Int
    private let historyMaxPageCount: Int
    private let calendarWeeksBack: Int
    /// Cleans up the device-local per-exercise "complete" flags when a
    /// standalone session is finalized from the conflict prompt.
    private let markedCompleteStore = MarkedCompleteStore()

    init(
        repository: HomeRepository,
        historyRepository: HistoryRepository,
        standaloneRepository: StandaloneWorkoutRepository,
        sessionManager: SessionManager,
        calendar: Calendar = .current,
        recentHistoryLimit: Int = 5,
        historyPageSize: Int = 50,
        historyMaxPageCount: Int = 10,
        calendarWeeksBack: Int = 52
    ) {
        self.repository = repository
        self.historyRepository = historyRepository
        self.standaloneRepository = standaloneRepository
        self.sessionManager = sessionManager
        self.calendar = calendar
        self.recentHistoryLimit = recentHistoryLimit
        self.historyPageSize = historyPageSize
        self.historyMaxPageCount = historyMaxPageCount
        self.calendarWeeksBack = calendarWeeksBack
    }

    // MARK: - Derived state

    var hasActiveProgram: Bool { activeProgram != nil }

    var hasActiveWorkout: Bool { activeWorkout != nil }

    /// The standalone session (if any) blocking a program-workout start —
    /// newest first, matching the server's /active ordering.
    var blockingStandaloneSession: StandaloneSessionListItemDTO? {
        activeStandaloneSessions.first
    }

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

    /// True when the selected date is strictly after today (drives whether the
    /// "Schedule a workout" CTA is offered — scheduling is future-only).
    var isSelectedDateInFuture: Bool {
        calendar.startOfDay(for: selectedDate) > calendar.startOfDay(for: .now)
    }

    /// First `recentHistoryLimit` rows of the accumulated history — the Home
    /// "History" preview. Pages accumulate newest-first, so the prefix equals
    /// what a dedicated limit-N fetch would return.
    var recentHistory: [HistoryEntryDTO] {
        Array(history.prefix(recentHistoryLimit))
    }

    /// All completed sessions (program + standalone) on the selected calendar
    /// day, newest first. The past-date view renders one card per entry — a
    /// program session and a standalone session can share a day.
    var completedEntriesForSelectedDate: [HistoryEntryDTO] {
        history.filter {
            $0.completedAt.map { calendar.isDate($0, inSameDayAs: selectedDate) } ?? false
        }
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

    /// Day-string keys ("yyyy-MM-dd") for dates with a completed session, used by
    /// the calendar to mark days the user finished a workout. Built from the
    /// unified history so standalone and prior-program completions count too —
    /// history rows are completed by definition, so no status filter is needed.
    var completedDateKeys: Set<String> {
        Set(history.compactMap { entry in
            entry.completedAt.map { Self.dayKey($0, calendar: calendar) }
        })
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
            // Kicked off in parallel but awaited below — history and standalone
            // sessions are secondary to the dashboard, so their failure
            // shouldn't blank out the rest of the page.
            async let historyTask = fetchCalendarHistory()
            async let standaloneSessionsTask = standaloneRepository.fetchActiveSessions()
            let (program, workout, sessions) = try await (activeProgramTask, activeWorkoutTask, sessionsTask)
            self.activeProgram = program
            self.activeWorkout = workout
            self.sessions = sessions

            do {
                // Assigned only when the whole paging loop succeeds — on a
                // refresh failure, stale highlights beat blanked ones.
                self.history = try await historyTask
            } catch {
                Logger.data.error("Failed to fetch history: \(error)")
            }

            do {
                self.activeStandaloneSessions = try await standaloneSessionsTask
            } catch {
                Logger.data.error("Failed to fetch active standalone sessions: \(error)")
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

    /// Completes (or discards) every in-progress standalone session so the
    /// program workout can start — the "one active workout at a time" prompt's
    /// action. Normally there's exactly one; iterating keeps the invariant
    /// even if the web app left extras behind. Returns true when clear.
    func resolveStandaloneSessions(discard: Bool) async -> Bool {
        startConflictError = nil
        do {
            // Iterate a snapshot and drop each session from the published list
            // as soon as it's resolved, so a mid-loop failure leaves only the
            // unresolved sessions behind — a retry won't re-complete (and 409
            // on) sessions that already went through.
            for session in activeStandaloneSessions {
                if discard {
                    try await standaloneRepository.abandonSession(id: session.id)
                } else {
                    _ = try await standaloneRepository.completeSession(id: session.id)
                }
                markedCompleteStore.clear(sessionId: session.id)
                activeStandaloneSessions.removeAll { $0.id == session.id }
            }
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch {
            Logger.data.error("resolveStandaloneSessions failed: \(error)")
            startConflictError = error.localizedDescription
            return false
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

    /// Oldest date the calendar strip can display. The strip pages -52 weeks
    /// from the start of the CURRENT WEEK — up to 6 days before today minus 52
    /// weeks — so one extra week of slack covers the earliest visible week.
    /// The month sheet can browse further back; days beyond this window are
    /// accepted as unhighlighted.
    private var calendarCutoff: Date {
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .weekOfYear, value: -(calendarWeeksBack + 1), to: today) ?? .distantPast
    }

    /// Pages GET /api/history newest-first until the server is exhausted
    /// (short page — the wire has no hasMore field), rows predate the calendar
    /// window, or the safety cap is hit.
    private func fetchCalendarHistory() async throws -> [HistoryEntryDTO] {
        let cutoff = calendarCutoff
        var accumulated: [HistoryEntryDTO] = []
        var cursor: (before: Date, id: String)?
        for _ in 0..<historyMaxPageCount {
            let page = try await historyRepository.fetchHistory(
                limit: historyPageSize,
                before: cursor?.before,
                beforeId: cursor?.id
            )
            accumulated.append(contentsOf: page)
            // A nil completedAt shouldn't occur on /api/history, but without it
            // the server's (before, beforeId) cursor pair can't be formed —
            // stop rather than loop.
            guard page.count >= historyPageSize,
                  let last = page.last, let lastCompletedAt = last.completedAt
            else { break }
            // Newest-first: once this page's oldest row predates the window,
            // everything older is off-screen. The boundary page is kept whole —
            // extra too-old rows are harmless, their day keys never render.
            if lastCompletedAt < cutoff { break }
            cursor = (lastCompletedAt, last.id)
        }
        return accumulated
    }

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
