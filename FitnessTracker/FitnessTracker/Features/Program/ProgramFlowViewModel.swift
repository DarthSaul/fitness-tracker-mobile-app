import Foundation
import Observation
import OSLog

enum DayStatus: Sendable, Equatable {
    case completed
    case inProgress
    case current
    case upcoming
}

@Observable
@MainActor
final class ProgramFlowViewModel {
    // MARK: - State
    var activeProgram: ActiveUserProgramDTO?
    var sessions: [ActiveProgramSessionDTO] = []
    var isLoading = false
    var loadError: Error?
    private(set) var isEndingProgram = false
    /// Surfaced when ending the program early fails.
    var actionError: String?

    // MARK: - Dependencies
    private let homeRepository: HomeRepository
    private let userProgramRepository: UserProgramRepository
    private let sessionManager: SessionManager

    init(
        homeRepository: HomeRepository,
        userProgramRepository: UserProgramRepository,
        sessionManager: SessionManager
    ) {
        self.homeRepository = homeRepository
        self.userProgramRepository = userProgramRepository
        self.sessionManager = sessionManager
    }

    // MARK: - Load
    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let programTask = homeRepository.fetchActiveUserProgram()
            async let sessionsTask = homeRepository.fetchActiveProgramSessions()
            let (program, sessions) = try await (programTask, sessionsTask)
            self.activeProgram = program
            self.sessions = sessions
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("ProgramFlowViewModel.load failed: \(error)")
            self.loadError = error
        }
    }

    // MARK: - End early

    /// The server 409s ending a run with no completed workouts (there is
    /// nothing to end at week 1 day 1), so the action stays hidden until then.
    var canEndProgramEarly: Bool {
        activeProgram != nil && sessions.contains { $0.status == .completed }
    }

    /// Ends the active run before its final day. Returns true when the run is
    /// over and the caller should leave this screen. Restarting is a separate
    /// "Start again" (activate) from the Programs tab.
    func endProgramEarly() async -> Bool {
        guard let userProgramId = activeProgram?.id, !isEndingProgram else { return false }
        isEndingProgram = true
        defer { isEndingProgram = false }

        do {
            try await userProgramRepository.completeProgram(userProgramId: userProgramId)
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch APIError.httpError(let statusCode, _, _) where statusCode == 409 {
            // Either the run turned terminal elsewhere (another device, or the
            // final day was just completed) — the outcome the user asked for
            // already holds — or it has no completed workouts yet. Ask the
            // server which: "no longer active" is not enough, since a run that
            // was merely paused elsewhere is still open.
            return await isRunOver(userProgramId: userProgramId)
        } catch {
            Logger.data.error("endProgramEarly failed for \(userProgramId): \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    /// Resolves a 409 from ending the run. True only when the refreshed run is
    /// terminal; otherwise the run is still open and the error is surfaced.
    private func isRunOver(userProgramId: String) async -> Bool {
        do {
            let runs = try await userProgramRepository.fetchUserPrograms()
            // The list holds one current run per program and omits archived
            // ones, so a run missing from it has been archived or superseded.
            guard let run = runs.first(where: { $0.id == userProgramId }) else { return true }
            if run.completedAt != nil || run.archivedAt != nil { return true }
            actionError = "This program can't be ended yet. Complete a workout first."
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch {
            Logger.data.error("Failed to refresh runs after a 409 on end early: \(error)")
            actionError = error.localizedDescription
        }
        // Still open: keep this screen current rather than dismissing it.
        await load()
        return false
    }

    // MARK: - Status

    func status(forWeek weekNumber: Int, day dayNumber: Int) -> DayStatus {
        if let s = sessionFor(week: weekNumber, day: dayNumber) {
            switch s.status {
            case .completed: return .completed
            case .inProgress, .editing: return .inProgress
            }
        }
        if let program = activeProgram,
           weekNumber == program.currentWeek,
           dayNumber == program.currentDay {
            return .current
        }
        return .upcoming
    }

    func sessionFor(week weekNumber: Int, day dayNumber: Int) -> ActiveProgramSessionDTO? {
        sessions.first { $0.weekNumber == weekNumber && $0.dayNumber == dayNumber }
    }

    /// Total template sets for a day, summed across exercise groups + exercises.
    func totalSetsFor(week weekNumber: Int, day dayNumber: Int) -> Int {
        guard let program = activeProgram,
              let week = program.program.weeks.first(where: { $0.weekNumber == weekNumber }),
              let day = week.days.first(where: { $0.dayNumber == dayNumber })
        else { return 0 }
        return day.exerciseGroups.reduce(0) { sum, group in
            sum + group.exercises.reduce(0) { $0 + $1.sets.count }
        }
    }

    /// True only when the day is the user's current position AND has an in-progress session.
    /// Live workouts at the current position should be locked from edit on this screen — they
    /// belong to the dedicated live-workout view (PR #7).
    func isLiveAtCurrentPosition(week weekNumber: Int, day dayNumber: Int) -> Bool {
        guard let program = activeProgram,
              weekNumber == program.currentWeek,
              dayNumber == program.currentDay,
              let s = sessionFor(week: weekNumber, day: dayNumber),
              s.status == .inProgress
        else { return false }
        return true
    }
}
