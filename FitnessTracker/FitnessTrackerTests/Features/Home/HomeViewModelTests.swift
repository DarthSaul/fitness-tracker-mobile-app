import Foundation
import Testing
@testable import FitnessTracker

@Suite("HomeViewModel")
@MainActor
struct HomeViewModelTests {
    // MARK: - Fixtures
    private func makeProgramDayDTO(_ id: String, dayNumber: Int) -> ProgramDayDTO {
        ProgramDayDTO(
            id: id, programWeekId: "w1", dayNumber: dayNumber,
            name: nil, warmUp: nil, exerciseGroups: []
        )
    }

    private func makeActiveProgram(
        id: String = "up1",
        currentWeek: Int = 1,
        currentDay: Int = 1,
        weeks: [(weekNumber: Int, days: Int)] = [(1, 3), (2, 3)]
    ) -> ActiveUserProgramDTO {
        let activeWeeks = weeks.map { spec in
            ActiveUserProgramDTO.ActiveProgramWeek(
                id: "w\(spec.weekNumber)", programId: "p1", weekNumber: spec.weekNumber,
                days: (1...spec.days).map { makeProgramDayDTO("d\(spec.weekNumber)-\($0)", dayNumber: $0) }
            )
        }
        return ActiveUserProgramDTO(
            id: id, userId: "u1", programId: "p1", isActive: true,
            currentWeek: currentWeek, currentDay: currentDay,
            startedAt: .now,
            program: ActiveUserProgramDTO.ActiveProgramDetail(
                id: "p1", name: "Test Program", description: nil,
                createdAt: .now, weeks: activeWeeks
            )
        )
    }

    private func makeSession(
        week: Int, day: Int, status: SessionStatus = .completed
    ) -> ActiveProgramSessionDTO {
        ActiveProgramSessionDTO(
            id: "s\(week)-\(day)", userId: "u1", userProgramId: "up1",
            weekNumber: week, dayNumber: day, status: status,
            startedAt: .now, completedAt: status == .completed ? .now : nil, notes: nil,
            count: ActiveProgramSessionDTO.Count(completedSets: 0)
        )
    }

    private func makeScheduled(id: String, week: Int, day: Int, on date: Date) -> ScheduledWorkoutDTO {
        ScheduledWorkoutDTO(
            id: id, userProgramId: "up1",
            weekNumber: week, dayNumber: day,
            scheduledDate: date, createdAt: .now
        )
    }

    private func makeViewModel(
        active: ActiveUserProgramDTO? = nil,
        sessions: [ActiveProgramSessionDTO] = [],
        scheduled: [ScheduledWorkoutDTO] = [],
        activeWorkout: ActiveWorkoutResponseDTO? = nil
    ) -> (HomeViewModel, MockAPIClient) {
        let client = MockAPIClient()
        if let active {
            client.stub(.getActiveUserProgram, response: active)
            client.stub(
                .getScheduledWorkouts(userProgramId: active.id, from: nil, to: nil),
                response: ScheduledWorkoutsResponseDTO(scheduledWorkouts: scheduled)
            )
        } else {
            client.handlers["/api/user-programs/active"] = { _ in
                throw APIError.httpError(statusCode: 404, data: Data())
            }
        }
        if let activeWorkout {
            client.stub(.getActiveWorkout, response: activeWorkout)
        } else {
            client.handlers["/api/workouts/active"] = { _ in
                throw APIError.httpError(statusCode: 404, data: Data())
            }
        }
        client.stub(
            .getActiveProgramSessions,
            response: ActiveProgramSessionsResponseDTO(sessions: sessions)
        )
        client.stub(
            .getWorkoutHistory(limit: 5, before: nil),
            response: WorkoutHistoryResponseDTO(sessions: [])
        )

        let repo = HomeRepository(apiClient: client)
        let historyRepo = HistoryRepository(apiClient: client)
        let session = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        let vm = HomeViewModel(
            repository: repo,
            historyRepository: historyRepo,
            sessionManager: session
        )
        return (vm, client)
    }

    // MARK: - Load

    @Test("load combines four sources and surfaces active program")
    func loadCombines() async throws {
        let active = makeActiveProgram(weeks: [(1, 3), (2, 3)])
        let (vm, _) = makeViewModel(
            active: active,
            sessions: [makeSession(week: 1, day: 1)],
            scheduled: [makeScheduled(id: "sw1", week: 1, day: 2, on: .now)]
        )

        await vm.load()

        #expect(vm.hasActiveProgram == true)
        #expect(vm.totalDays == 6)
        #expect(vm.completedDays == 1)
        #expect(vm.scheduledWorkouts.count == 1)
    }

    @Test("load with no active program leaves empty state without error")
    func loadNoActive() async throws {
        let (vm, _) = makeViewModel()
        await vm.load()
        #expect(vm.hasActiveProgram == false)
        #expect(vm.scheduledWorkouts.isEmpty)
        #expect(vm.loadError == nil)
    }

    // MARK: - Derived

    @Test("progressPercent rounds to nearest integer 0...100")
    func progressClamped() async throws {
        let active = makeActiveProgram(weeks: [(1, 4)])
        let (vm, _) = makeViewModel(
            active: active,
            sessions: [
                makeSession(week: 1, day: 1),
                makeSession(week: 1, day: 2),
            ]
        )
        await vm.load()
        #expect(vm.progressPercent == 50)
    }

    @Test("nextWorkoutDay points at the program's currentWeek/currentDay")
    func nextWorkout() async throws {
        let active = makeActiveProgram(currentWeek: 2, currentDay: 2)
        let (vm, _) = makeViewModel(active: active)
        await vm.load()
        #expect(vm.nextWorkoutDay?.dayNumber == 2)
        #expect(vm.nextWorkoutDay?.id == "d2-2")
    }

    @Test("schedule(forWeek:day:) finds an existing entry and ignores others")
    func scheduleLookup() async throws {
        let active = makeActiveProgram()
        let (vm, _) = makeViewModel(
            active: active,
            scheduled: [
                makeScheduled(id: "sw1", week: 1, day: 2, on: .now),
                makeScheduled(id: "sw2", week: 2, day: 1, on: .now),
            ]
        )
        await vm.load()
        #expect(vm.schedule(forWeek: 1, day: 2)?.id == "sw1")
        #expect(vm.schedule(forWeek: 2, day: 1)?.id == "sw2")
        #expect(vm.schedule(forWeek: 1, day: 1) == nil)
    }

    // MARK: - Schedule mutations

    @Test("schedule POSTs and refreshes the scheduled list")
    func scheduleRoundTrip() async throws {
        let active = makeActiveProgram()
        let (vm, client) = makeViewModel(active: active)
        await vm.load()
        #expect(vm.scheduledWorkouts.isEmpty)

        let newScheduled = makeScheduled(id: "sw-new", week: 1, day: 2, on: vm.selectedDate)
        client.stub(
            .scheduleWorkout(ScheduleWorkoutBody(
                userProgramId: active.id, weekNumber: 1, dayNumber: 2, scheduledDate: vm.selectedDate
            )),
            response: ScheduleWorkoutResponseDTO(scheduledWorkout: newScheduled)
        )
        // The post-schedule refresh re-fetches the list — re-stub it.
        client.stub(
            .getScheduledWorkouts(userProgramId: active.id, from: nil, to: nil),
            response: ScheduledWorkoutsResponseDTO(scheduledWorkouts: [newScheduled])
        )

        await vm.schedule(weekNumber: 1, dayNumber: 2)

        #expect(vm.scheduledWorkouts.count == 1)
        #expect(vm.scheduleError == nil)
    }

    @Test("unscheduleSelected DELETEs and refreshes")
    func unscheduleRoundTrip() async throws {
        let active = makeActiveProgram()
        // Use a fixed date instead of .now to keep the test deterministic at
        // midnight crossings — the VM matches scheduled workouts to selectedDate
        // by calendar day, and `.now` evaluated twice could land on different days.
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let target = makeScheduled(id: "sw1", week: 1, day: 1, on: fixedDate)
        let (vm, client) = makeViewModel(
            active: active,
            scheduled: [target]
        )
        await vm.load()
        vm.selectedDate = fixedDate

        client.stub(.unscheduleWorkout(id: "sw1"), response: ["ok": true])
        client.stub(
            .getScheduledWorkouts(userProgramId: active.id, from: nil, to: nil),
            response: ScheduledWorkoutsResponseDTO(scheduledWorkouts: [])
        )

        await vm.unscheduleSelected()

        #expect(vm.scheduledWorkouts.isEmpty)
        #expect(vm.scheduleError == nil)
    }

    // MARK: - Day key helper

    @Test("dayKey produces stable yyyy-MM-dd strings")
    func dayKeyFormat() {
        var components = DateComponents()
        components.year = 2026; components.month = 5; components.day = 3
        components.hour = 14; components.minute = 30
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let key = HomeViewModel.dayKey(date)
        #expect(key.hasPrefix("2026-05-"))
        #expect(key.count == 10)
    }
}
