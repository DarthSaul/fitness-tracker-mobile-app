import Foundation
import Testing
@testable import FitnessTracker

@Suite("ProgramFlowViewModel")
@MainActor
struct ProgramFlowViewModelTests {
    private func makeProgramDayDTO(_ id: String, dayNumber: Int, sets: Int = 3) -> ProgramDayDTO {
        let templateSets = (1...sets).map { i in
            ExerciseSetDTO(
                id: "es-\(id)-\(i)", programExerciseId: "pe-\(id)",
                setNumber: i, reps: 5, weight: 100, rpe: nil,
                notes: nil, effortTarget: nil
            )
        }
        let exercise = ProgramExerciseDTO(
            id: "pe-\(id)", exerciseGroupId: "g-\(id)", exerciseId: "ex1",
            order: 0,
            exercise: ExerciseDTO(id: "ex1", name: "Bench", description: nil),
            sets: templateSets
        )
        let group = ExerciseGroupDTO(
            id: "g-\(id)", programDayId: id, order: 0,
            type: .standard, restSeconds: 90, exercises: [exercise]
        )
        return ProgramDayDTO(
            id: id, programWeekId: "w1", dayNumber: dayNumber,
            name: nil, warmUp: nil, exerciseGroups: [group]
        )
    }

    private func makeActiveProgram(currentWeek: Int = 2, currentDay: Int = 2) -> ActiveUserProgramDTO {
        let weeks = [1, 2].map { weekNumber in
            ActiveUserProgramDTO.ActiveProgramWeek(
                id: "w\(weekNumber)", programId: "p1", weekNumber: weekNumber,
                days: (1...3).map { makeProgramDayDTO("d\(weekNumber)-\($0)", dayNumber: $0) }
            )
        }
        return ActiveUserProgramDTO(
            id: "up1", userId: "u1", programId: "p1", isActive: true,
            currentWeek: currentWeek, currentDay: currentDay,
            startedAt: .now,
            program: ActiveUserProgramDTO.ActiveProgramDetail(
                id: "p1", name: "Test", description: nil,
                createdAt: .now, weeks: weeks
            )
        )
    }

    private func makeSession(week: Int, day: Int, status: SessionStatus, completedSets: Int = 0) -> ActiveProgramSessionDTO {
        ActiveProgramSessionDTO(
            id: "s\(week)-\(day)", userId: "u1", userProgramId: "up1",
            weekNumber: week, dayNumber: day, status: status,
            startedAt: .now, completedAt: status == .completed ? .now : nil,
            notes: nil,
            count: ActiveProgramSessionDTO.Count(completedSets: completedSets)
        )
    }

    private func makeViewModel(
        active: ActiveUserProgramDTO?,
        sessions: [ActiveProgramSessionDTO]
    ) -> ProgramFlowViewModel {
        let client = MockAPIClient()
        if let active {
            client.stub(.getActiveUserProgram, response: active)
        } else {
            client.handlers["/api/user-programs/active"] = { _ in throw APIError.httpError(statusCode: 404, data: Data()) }
        }
        client.stub(.getActiveProgramSessions, response: ActiveProgramSessionsResponseDTO(sessions: sessions))

        let homeRepo = HomeRepository(apiClient: client)
        let session = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        return ProgramFlowViewModel(homeRepository: homeRepo, sessionManager: session)
    }

    @Test("status returns .completed when a completed session exists")
    func statusCompleted() async {
        let vm = makeViewModel(
            active: makeActiveProgram(),
            sessions: [makeSession(week: 1, day: 1, status: .completed)]
        )
        await vm.load()
        #expect(vm.status(forWeek: 1, day: 1) == .completed)
    }

    @Test("status returns .inProgress for IN_PROGRESS or EDITING sessions")
    func statusInProgress() async {
        let vm = makeViewModel(
            active: makeActiveProgram(),
            sessions: [
                makeSession(week: 1, day: 2, status: .inProgress),
                makeSession(week: 1, day: 3, status: .editing),
            ]
        )
        await vm.load()
        #expect(vm.status(forWeek: 1, day: 2) == .inProgress)
        #expect(vm.status(forWeek: 1, day: 3) == .inProgress)
    }

    @Test("status returns .current for the program's currentWeek/currentDay with no session")
    func statusCurrent() async {
        let vm = makeViewModel(
            active: makeActiveProgram(currentWeek: 2, currentDay: 2),
            sessions: []
        )
        await vm.load()
        #expect(vm.status(forWeek: 2, day: 2) == .current)
    }

    @Test("status returns .upcoming for everything else")
    func statusUpcoming() async {
        let vm = makeViewModel(
            active: makeActiveProgram(currentWeek: 2, currentDay: 2),
            sessions: []
        )
        await vm.load()
        #expect(vm.status(forWeek: 2, day: 3) == .upcoming)
        #expect(vm.status(forWeek: 1, day: 1) == .upcoming)
    }

    @Test("totalSetsFor sums template sets across exercises")
    func totalSetsCount() async {
        let vm = makeViewModel(active: makeActiveProgram(), sessions: [])
        await vm.load()
        // Each day has 1 exercise with 3 sets.
        #expect(vm.totalSetsFor(week: 1, day: 1) == 3)
    }

    @Test("isLiveAtCurrentPosition only true when in-progress at current position")
    func liveAtCurrent() async {
        let vm = makeViewModel(
            active: makeActiveProgram(currentWeek: 2, currentDay: 2),
            sessions: [
                makeSession(week: 2, day: 2, status: .inProgress),
                makeSession(week: 2, day: 1, status: .inProgress), // not current pos
                makeSession(week: 1, day: 1, status: .editing),    // EDITING isn't 'live'
            ]
        )
        await vm.load()
        #expect(vm.isLiveAtCurrentPosition(week: 2, day: 2) == true)
        #expect(vm.isLiveAtCurrentPosition(week: 2, day: 1) == false)
        #expect(vm.isLiveAtCurrentPosition(week: 1, day: 1) == false)
    }
}
