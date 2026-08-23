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

    private func makeStandaloneSession(id: String, workoutId: String = "sw1") -> StandaloneSessionListItemDTO {
        StandaloneSessionListItemDTO(
            id: id, userId: "u1", standaloneWorkoutId: workoutId,
            status: .inProgress, startedAt: .now, completedAt: nil, notes: nil,
            count: StandaloneSessionListItemDTO.Count(completedSets: 2),
            standaloneWorkout: StandaloneSessionListItemDTO.WorkoutRef(
                id: workoutId, category: "Arms Only", order: 1, name: nil
            )
        )
    }

    private func makeProgramHistoryEntry(
        id: String, completedAt: Date?, userProgramId: String = "up1"
    ) -> HistoryEntryDTO {
        .program(HistorySessionDTO(
            id: id, userId: "u1", userProgramId: userProgramId,
            programName: "Test Program",
            weekNumber: 1, dayNumber: 1, status: .completed,
            startedAt: completedAt ?? .now, completedAt: completedAt, notes: nil,
            count: HistorySessionDTO.Count(completedSets: 5)
        ))
    }

    private func makeStandaloneHistoryEntry(
        id: String, completedAt: Date?
    ) -> HistoryEntryDTO {
        .standalone(StandaloneSessionListItemDTO(
            id: id, userId: "u1", standaloneWorkoutId: "sw1",
            status: .completed, startedAt: completedAt ?? .now, completedAt: completedAt, notes: nil,
            count: StandaloneSessionListItemDTO.Count(completedSets: 3),
            standaloneWorkout: StandaloneSessionListItemDTO.WorkoutRef(
                id: "sw1", category: "KB Only", order: 1, name: nil
            )
        ))
    }

    private func makeViewModel(
        active: ActiveUserProgramDTO? = nil,
        sessions: [ActiveProgramSessionDTO] = [],
        scheduled: [ScheduledWorkoutDTO] = [],
        activeWorkout: ActiveWorkoutResponseDTO? = nil,
        activeStandalone: [StandaloneSessionListItemDTO] = [],
        historyPageSize: Int = 50,
        historyMaxPageCount: Int = 10,
        calendarWeeksBack: Int = 52
    ) -> (HomeViewModel, MockAPIClient) {
        let client = MockAPIClient()
        if let active {
            client.stub(.getActiveUserProgram, response: active)
            client.stub(
                .getScheduledWorkouts(userProgramId: active.id, from: nil, to: nil),
                response: ScheduledWorkoutsResponseDTO(scheduledWorkouts: scheduled)
            )
        } else {
            client.handlers["GET /api/user-programs/active"] = { _ in
                throw APIError.httpError(statusCode: 404, message: nil, data: Data())
            }
        }
        if let activeWorkout {
            client.stub(.getActiveWorkout, response: activeWorkout)
        } else {
            client.handlers["GET /api/workouts/active"] = { _ in
                throw APIError.httpError(statusCode: 404, message: nil, data: Data())
            }
        }
        client.stub(
            .getActiveProgramSessions,
            response: ActiveProgramSessionsResponseDTO(sessions: sessions)
        )
        // MockAPIClient keys handlers by "GET /api/history" only, so this one
        // stub answers every page request; the empty page ends the paging loop
        // after a single call. Paging tests install their own closure handler.
        client.stub(
            .getHistory(type: nil, limit: historyPageSize, before: nil, beforeId: nil),
            response: HistoryResponseDTO(sessions: [])
        )
        client.stub(
            .getActiveStandaloneSessions,
            response: StandaloneSessionListResponseDTO(sessions: activeStandalone)
        )

        let repo = HomeRepository(apiClient: client)
        let historyRepo = HistoryRepository(apiClient: client)
        let standaloneRepo = StandaloneWorkoutRepository(apiClient: client)
        let session = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        let vm = HomeViewModel(
            repository: repo,
            historyRepository: historyRepo,
            standaloneRepository: standaloneRepo,
            sessionManager: session,
            historyPageSize: historyPageSize,
            historyMaxPageCount: historyMaxPageCount,
            calendarWeeksBack: calendarWeeksBack
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

    @Test("completedEntriesForSelectedDate returns every completion on the day, across types")
    func completedForSelectedDate() async throws {
        // Anchor at local noon so the one-hour offset below can't cross a
        // day boundary in any timezone.
        let past = Date(timeIntervalSince1970: 1_700_000_000)
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: past)!
        let (vm, _) = makeViewModel(active: makeActiveProgram())
        vm.history = [
            makeProgramHistoryEntry(id: "hp", completedAt: noon),
            makeStandaloneHistoryEntry(id: "hs", completedAt: noon.addingTimeInterval(-3600)),
        ]

        vm.selectedDate = Calendar.current.startOfDay(for: noon)
        #expect(vm.completedEntriesForSelectedDate.map(\.id) == ["hp", "hs"])

        // A different day has no completed sessions.
        vm.selectedDate = Calendar.current.startOfDay(for: .now)
        #expect(vm.completedEntriesForSelectedDate.isEmpty)
    }

    @Test("history entries without a completedAt are excluded from keys and day entries")
    func nilCompletedAtExcluded() async throws {
        let (vm, _) = makeViewModel(active: makeActiveProgram())
        vm.history = [makeStandaloneHistoryEntry(id: "hs", completedAt: nil)]
        vm.selectedDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(vm.completedEntriesForSelectedDate.isEmpty)
        #expect(vm.completedDateKeys.isEmpty)
    }

    @Test("completedDateKeys come from unified history, mixing program and standalone")
    func completedKeysFromHistory() async throws {
        let dayA = Date(timeIntervalSince1970: 1_700_000_000)
        let dayB = dayA.addingTimeInterval(-86_400 * 3)
        // No active program at all — highlights must not depend on one.
        let (vm, _) = makeViewModel()
        vm.history = [
            makeProgramHistoryEntry(id: "h1", completedAt: dayA, userProgramId: "up-old"),
            makeStandaloneHistoryEntry(id: "h2", completedAt: dayB),
        ]
        #expect(vm.completedDateKeys == [HomeViewModel.dayKey(dayA), HomeViewModel.dayKey(dayB)])
    }

    @Test("isSelectedDateInFuture is true only for dates after today")
    func futureDetection() async throws {
        let (vm, _) = makeViewModel(active: makeActiveProgram())
        vm.selectedDate = Calendar.current.date(byAdding: .day, value: 3, to: .now)!
        #expect(vm.isSelectedDateInFuture == true)
        vm.selectedDate = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        #expect(vm.isSelectedDateInFuture == false)
        vm.selectedDate = Calendar.current.startOfDay(for: .now)
        #expect(vm.isSelectedDateInFuture == false)
    }

    // MARK: - History paging

    @Test("recentHistory is the first five rows of the accumulated history")
    func recentHistoryPrefix() async throws {
        let (vm, client) = makeViewModel()
        let entries = (0..<7).map { i in
            makeProgramHistoryEntry(id: "h\(i)", completedAt: Date(timeIntervalSinceNow: -Double(i) * 86_400))
        }
        client.stub(
            .getHistory(type: nil, limit: 50, before: nil, beforeId: nil),
            response: HistoryResponseDTO(sessions: entries)
        )

        await vm.load()

        #expect(vm.history.count == 7)
        #expect(vm.recentHistory.map(\.id) == ["h0", "h1", "h2", "h3", "h4"])
    }

    @Test("paging carries the composite cursor forward and stops on a short page")
    func historyPaging() async throws {
        let (vm, client) = makeViewModel(historyPageSize: 2)
        // Whole-second dates survive the encode/decode round trip exactly, so
        // the captured cursor can be compared against the fixture directly.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())
        let page1 = [
            makeProgramHistoryEntry(id: "a", completedAt: now.addingTimeInterval(-86_400)),
            makeStandaloneHistoryEntry(id: "b", completedAt: now.addingTimeInterval(-2 * 86_400)),
        ]
        let page2 = [makeProgramHistoryEntry(id: "c", completedAt: now.addingTimeInterval(-3 * 86_400))]
        var calls: [(before: Date?, beforeId: String?)] = []
        client.handlers["GET /api/history"] = { endpoint in
            guard case .getHistory(_, _, let before, let beforeId) = endpoint else {
                throw APIError.missingHandler(path: "GET /api/history")
            }
            calls.append((before, beforeId))
            let page = before == nil ? page1 : page2
            return try JSONCoding.encoder.encode(HistoryResponseDTO(sessions: page))
        }

        await vm.load()

        #expect(calls.count == 2)
        #expect(calls.last?.before == now.addingTimeInterval(-2 * 86_400))
        #expect(calls.last?.beforeId == "b")
        #expect(vm.history.map(\.id) == ["a", "b", "c"])
    }

    @Test("paging stops once a full page reaches past the calendar window")
    func historyPagingCutoff() async throws {
        let (vm, client) = makeViewModel(historyPageSize: 2, calendarWeeksBack: 1)
        var callCount = 0
        let page = [
            makeProgramHistoryEntry(id: "a", completedAt: Date(timeIntervalSinceNow: -86_400)),
            // Past the 1(+1 slack)-week window — a full page ending here must
            // still be kept whole, but no further page requested.
            makeStandaloneHistoryEntry(id: "b", completedAt: Date(timeIntervalSinceNow: -30 * 86_400)),
        ]
        client.handlers["GET /api/history"] = { _ in
            callCount += 1
            return try JSONCoding.encoder.encode(HistoryResponseDTO(sessions: page))
        }

        await vm.load()

        #expect(callCount == 1)
        #expect(vm.history.map(\.id) == ["a", "b"])
    }

    @Test("paging stops at the page cap")
    func historyPagingCap() async throws {
        let (vm, client) = makeViewModel(historyPageSize: 2, historyMaxPageCount: 3)
        var callCount = 0
        client.handlers["GET /api/history"] = { _ in
            callCount += 1
            let base = -Double(callCount) * 86_400
            return try JSONCoding.encoder.encode(HistoryResponseDTO(sessions: [
                self.makeProgramHistoryEntry(id: "p\(callCount)-1", completedAt: Date(timeIntervalSinceNow: base)),
                self.makeProgramHistoryEntry(id: "p\(callCount)-2", completedAt: Date(timeIntervalSinceNow: base - 3600)),
            ]))
        }

        await vm.load()

        #expect(callCount == 3)
        #expect(vm.history.count == 6)
    }

    @Test("a history fetch failure is non-fatal and keeps prior data")
    func historyFailureNonFatal() async throws {
        let (vm, client) = makeViewModel(active: makeActiveProgram())
        client.handlers["GET /api/history"] = { _ in
            throw APIError.httpError(statusCode: 500, message: nil, data: Data())
        }

        await vm.load()

        #expect(vm.loadError == nil)
        #expect(vm.hasActiveProgram == true)
        #expect(vm.history.isEmpty)

        // A failed refresh keeps the previously loaded history rather than
        // blanking the calendar.
        vm.history = [makeProgramHistoryEntry(id: "keep", completedAt: .now)]
        await vm.load()
        #expect(vm.history.map(\.id) == ["keep"])
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

    // MARK: - Standalone conflict (one active workout at a time)

    @Test("blockingStandaloneSession surfaces the newest active standalone session")
    func blockingStandaloneSurfaces() async throws {
        let (vm, _) = makeViewModel(activeStandalone: [
            makeStandaloneSession(id: "ss1"),
            makeStandaloneSession(id: "ss2", workoutId: "sw2")
        ])
        await vm.load()

        #expect(vm.blockingStandaloneSession?.id == "ss1")
    }

    @Test("resolveStandaloneSessions(discard:) abandons every session and clears the list")
    func resolveByDiscard() async throws {
        let (vm, client) = makeViewModel(activeStandalone: [makeStandaloneSession(id: "ss1")])
        await vm.load()
        client.stub(.abandonStandaloneSession(id: "ss1"), response: ["success": true])

        #expect(await vm.resolveStandaloneSessions(discard: true))
        #expect(vm.activeStandaloneSessions.isEmpty)
        #expect(vm.blockingStandaloneSession == nil)
        #expect(vm.startConflictError == nil)
    }

    @Test("resolveStandaloneSessions completes sessions when not discarding")
    func resolveByComplete() async throws {
        let (vm, client) = makeViewModel(activeStandalone: [makeStandaloneSession(id: "ss1")])
        await vm.load()
        client.stub(
            .completeStandaloneSession(id: "ss1", body: nil),
            response: StandaloneSessionResponseDTO(session: StandaloneWorkoutSessionDTO(
                id: "ss1", userId: "u1", standaloneWorkoutId: "sw1",
                status: .completed, startedAt: .now, completedAt: .now, notes: nil
            ))
        )

        #expect(await vm.resolveStandaloneSessions(discard: false))
        #expect(vm.activeStandaloneSessions.isEmpty)
    }

    @Test("a mid-loop failure keeps only the unresolved sessions for retry")
    func resolvePartialFailure() async throws {
        let (vm, client) = makeViewModel(activeStandalone: [
            makeStandaloneSession(id: "ss1"),
            makeStandaloneSession(id: "ss2", workoutId: "sw2")
        ])
        await vm.load()
        client.stub(.abandonStandaloneSession(id: "ss1"), response: ["success": true])
        client.handlers["DELETE /api/standalone-workout-sessions/ss2"] = { _ in
            throw APIError.httpError(statusCode: 500, message: "boom", data: Data())
        }

        #expect(await vm.resolveStandaloneSessions(discard: true) == false)
        // ss1 resolved and removed; ss2 failed and stays for a retry.
        #expect(vm.activeStandaloneSessions.map(\.id) == ["ss2"])
        #expect(vm.startConflictError != nil)
    }

    @Test("unauthorized during resolve returns false")
    func resolveUnauthorized() async throws {
        let (vm, client) = makeViewModel(activeStandalone: [makeStandaloneSession(id: "ss1")])
        await vm.load()
        client.stubUnauthorized(for: .abandonStandaloneSession(id: "ss1"))

        #expect(await vm.resolveStandaloneSessions(discard: true) == false)
    }
}
