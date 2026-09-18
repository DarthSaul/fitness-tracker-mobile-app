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
        sessions: [ActiveProgramSessionDTO],
        client: MockAPIClient = MockAPIClient()
    ) -> ProgramFlowViewModel {
        if let active {
            client.stub(.getActiveUserProgram, response: active)
        } else {
            client.handlers["GET /api/user-programs/active"] = { _ in throw APIError.httpError(statusCode: 404, message: nil, data: Data()) }
        }
        client.stub(.getActiveProgramSessions, response: ActiveProgramSessionsResponseDTO(sessions: sessions))

        let homeRepo = HomeRepository(apiClient: client)
        let session = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        return ProgramFlowViewModel(
            homeRepository: homeRepo,
            userProgramRepository: UserProgramRepository(apiClient: client),
            sessionManager: session
        )
    }

    private let voidStub: [String: Bool] = ["ok": true]

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

    // MARK: - End early

    @Test("canEndProgramEarly needs a completed workout in the run")
    func canEndEarlyRequiresCompletedSession() async {
        let fresh = makeViewModel(
            active: makeActiveProgram(currentWeek: 1, currentDay: 1),
            sessions: [makeSession(week: 1, day: 1, status: .inProgress)]
        )
        await fresh.load()
        #expect(fresh.canEndProgramEarly == false)

        let underway = makeViewModel(
            active: makeActiveProgram(),
            sessions: [makeSession(week: 1, day: 1, status: .completed)]
        )
        await underway.load()
        #expect(underway.canEndProgramEarly == true)
    }

    @Test("endProgramEarly completes the active run and reports success")
    func endProgramEarlySuccess() async {
        let client = MockAPIClient()
        client.stub(.completeProgram(userProgramId: "up1"), response: voidStub)
        let vm = makeViewModel(
            active: makeActiveProgram(),
            sessions: [makeSession(week: 1, day: 1, status: .completed)],
            client: client
        )
        await vm.load()

        let ended = await vm.endProgramEarly()
        #expect(ended == true)
        #expect(vm.actionError == nil)
        #expect(vm.isEndingProgram == false)
    }

    private func makeRun(
        id: String = "up1", isActive: Bool, completedAt: Date? = nil
    ) -> UserProgramWithProgramDTO {
        UserProgramWithProgramDTO(
            id: id, userId: "u1", programId: "p1", isActive: isActive,
            currentWeek: 2, currentDay: 2, startedAt: .now,
            program: UserProgramWithProgramDTO.NestedProgram(id: "p1", name: "Test", description: nil),
            completedAt: completedAt
        )
    }

    /// A view model whose complete call 409s, with `runs` as the refreshed list.
    private func makeConflictingViewModel(runs: [UserProgramWithProgramDTO]) async -> ProgramFlowViewModel {
        let client = MockAPIClient()
        client.handlers["PATCH /api/user-programs/up1/complete"] = { _ in
            throw APIError.httpError(statusCode: 409, message: "Program already completed", data: Data())
        }
        client.stub(.getUserPrograms, response: runs)
        let vm = makeViewModel(
            active: makeActiveProgram(),
            sessions: [makeSession(week: 1, day: 1, status: .completed)],
            client: client
        )
        await vm.load()
        return vm
    }

    @Test("endProgramEarly treats a 409 as ended when the refreshed run is completed")
    func endProgramEarlyConflictAlreadyEnded() async {
        let vm = await makeConflictingViewModel(runs: [makeRun(isActive: false, completedAt: .now)])

        let ended = await vm.endProgramEarly()
        #expect(ended == true)
        #expect(vm.actionError == nil)
    }

    @Test("endProgramEarly treats a 409 as ended when the run left the library")
    func endProgramEarlyConflictRunGone() async {
        // Archived runs are omitted, and a restart supersedes the old id.
        let vm = await makeConflictingViewModel(runs: [makeRun(id: "up2", isActive: true)])

        let ended = await vm.endProgramEarly()
        #expect(ended == true)
        #expect(vm.actionError == nil)
    }

    @Test("endProgramEarly surfaces a 409 when the run is still open")
    func endProgramEarlyConflictStillOpen() async {
        let vm = await makeConflictingViewModel(runs: [makeRun(isActive: true)])

        let ended = await vm.endProgramEarly()
        #expect(ended == false)
        #expect(vm.actionError != nil)
    }

    @Test("a 409 on a run that was only paused elsewhere is not treated as ended")
    func endProgramEarlyConflictPausedElsewhere() async {
        // No longer the active run, but still open — must not report success.
        let vm = await makeConflictingViewModel(runs: [makeRun(isActive: false)])

        let ended = await vm.endProgramEarly()
        #expect(ended == false)
        #expect(vm.actionError != nil)
    }

    @Test("endProgramEarly surfaces other failures and stays on screen")
    func endProgramEarlyFailure() async {
        let client = MockAPIClient()
        client.handlers["PATCH /api/user-programs/up1/complete"] = { _ in
            throw APIError.httpError(statusCode: 500, message: "Failed to complete program", data: Data())
        }
        let vm = makeViewModel(
            active: makeActiveProgram(),
            sessions: [makeSession(week: 1, day: 1, status: .completed)],
            client: client
        )
        await vm.load()

        let ended = await vm.endProgramEarly()
        #expect(ended == false)
        #expect(vm.actionError == "Failed to complete program")
    }
}
