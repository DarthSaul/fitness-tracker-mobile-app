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

    // MARK: - Dependencies
    private let homeRepository: HomeRepository
    private let sessionManager: SessionManager

    init(homeRepository: HomeRepository, sessionManager: SessionManager) {
        self.homeRepository = homeRepository
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
