import Foundation
import Testing
@testable import FitnessTracker

@Suite("StandaloneWorkoutDetailViewModel")
@MainActor
struct StandaloneWorkoutDetailViewModelTests {
    // MARK: - Fixtures

    private func makeWorkout(id: String = "sw1") -> StandaloneWorkoutDetailDTO {
        StandaloneWorkoutDetailDTO(
            id: id, category: "Lower Body", order: 1, name: nil,
            description: nil, createdAt: .now, groups: []
        )
    }

    private func makeListItem(id: String = "ss1", workoutId: String = "sw1") -> StandaloneSessionListItemDTO {
        StandaloneSessionListItemDTO(
            id: id, userId: "u1", standaloneWorkoutId: workoutId,
            status: .inProgress, startedAt: .now, completedAt: nil, notes: nil,
            count: StandaloneSessionListItemDTO.Count(completedSets: 2),
            standaloneWorkout: StandaloneSessionListItemDTO.WorkoutRef(
                id: workoutId, category: "Lower Body", order: 1, name: nil
            )
        )
    }

    private func makeProgramActiveResponse() -> ActiveWorkoutResponseDTO {
        ActiveWorkoutResponseDTO(
            session: ActiveWorkoutResponseDTO.ActiveWorkoutSession(
                id: "ws1", userId: "u1", userProgramId: "up1",
                weekNumber: 2, dayNumber: 3, status: .inProgress,
                startedAt: .now, completedAt: nil, notes: nil,
                completedSets: [],
                userProgram: UserProgramDTO(
                    id: "up1", userId: "u1", programId: "p1", isActive: true,
                    currentWeek: 2, currentDay: 3, startedAt: .now
                ),
                workoutExerciseSwaps: []
            ),
            day: ProgramDayDTO(id: "d1", programWeekId: "w1", dayNumber: 3, name: nil, warmUp: nil, exerciseGroups: [])
        )
    }

    private func stubNoProgramWorkout(_ client: MockAPIClient) {
        client.handlers["GET /api/workouts/active"] = { _ in
            throw APIError.httpError(statusCode: 404, message: nil, data: Data())
        }
    }

    private func stubActiveStandaloneSessions(_ client: MockAPIClient, _ sessions: [StandaloneSessionListItemDTO]) {
        client.stub(.getActiveStandaloneSessions, response: StandaloneSessionListResponseDTO(sessions: sessions))
    }

    private func makeViewModel(client: MockAPIClient) -> StandaloneWorkoutDetailViewModel {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return StandaloneWorkoutDetailViewModel(
            workoutId: "sw1",
            repository: StandaloneWorkoutRepository(apiClient: client),
            workoutRepository: WorkoutRepository(apiClient: client),
            sessionManager: SessionManager(keychain: KeychainService(), tokenStore: TokenStore()),
            markedCompleteStore: MarkedCompleteStore(defaults: defaults)
        )
    }

    // MARK: - Start / resume

    @Test("startOrResume starts cleanly when nothing is in progress")
    func startClean() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneWorkout(id: "sw1"), response: makeWorkout())
        stubNoProgramWorkout(client)
        stubActiveStandaloneSessions(client, [])
        client.stub(
            .createStandaloneSession(CreateStandaloneSessionBody(standaloneWorkoutId: "sw1")),
            response: StandaloneSessionResponseDTO(session: StandaloneWorkoutSessionDTO(
                id: "ss-new", userId: "u1", standaloneWorkoutId: "sw1",
                status: .inProgress, startedAt: .now, completedAt: nil, notes: nil
            ))
        )
        let vm = makeViewModel(client: client)
        await vm.load()

        let sessionId = await vm.startOrResume()
        #expect(sessionId == "ss-new")
        #expect(vm.blocker == nil)
    }

    @Test("startOrResume resumes the existing session for this workout")
    func resumeExisting() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneWorkout(id: "sw1"), response: makeWorkout())
        stubActiveStandaloneSessions(client, [makeListItem(id: "ss1", workoutId: "sw1")])
        let vm = makeViewModel(client: client)
        await vm.load()

        #expect(vm.activeSessionForThisWorkout?.id == "ss1")
        // No start POST is stubbed — resume must short-circuit before it.
        let sessionId = await vm.startOrResume()
        #expect(sessionId == "ss1")
    }

    @Test("an active program workout blocks the start with a prompt")
    func programBlocks() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneWorkout(id: "sw1"), response: makeWorkout())
        stubActiveStandaloneSessions(client, [])
        client.stub(.getActiveWorkout, response: makeProgramActiveResponse())
        let vm = makeViewModel(client: client)
        await vm.load()

        let sessionId = await vm.startOrResume()
        #expect(sessionId == nil)
        if case .program(let session)? = vm.blocker {
            #expect(session.id == "ws1")
        } else {
            Issue.record("expected a program blocker")
        }
    }

    @Test("a different standalone session blocks the start with a prompt")
    func otherStandaloneBlocks() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneWorkout(id: "sw1"), response: makeWorkout())
        stubNoProgramWorkout(client)
        // Active session belongs to a DIFFERENT workout (sw2).
        stubActiveStandaloneSessions(client, [makeListItem(id: "ss2", workoutId: "sw2")])
        let vm = makeViewModel(client: client)
        await vm.load()

        let sessionId = await vm.startOrResume()
        #expect(sessionId == nil)
        if case .standalone(let session)? = vm.blocker {
            #expect(session.id == "ss2")
        } else {
            Issue.record("expected a standalone blocker")
        }
    }

    @Test("resolveBlockerAndStart discards the blocking standalone session then starts")
    func resolveByDiscard() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneWorkout(id: "sw1"), response: makeWorkout())
        stubNoProgramWorkout(client)
        stubActiveStandaloneSessions(client, [makeListItem(id: "ss2", workoutId: "sw2")])
        let vm = makeViewModel(client: client)
        await vm.load()
        _ = await vm.startOrResume()
        let blocker = try #require(vm.blocker)

        client.stub(.abandonStandaloneSession(id: "ss2"), response: ["success": true])
        // After the discard, the re-check comes back clear and the start succeeds.
        stubActiveStandaloneSessions(client, [])
        client.stub(
            .createStandaloneSession(CreateStandaloneSessionBody(standaloneWorkoutId: "sw1")),
            response: StandaloneSessionResponseDTO(session: StandaloneWorkoutSessionDTO(
                id: "ss-new", userId: "u1", standaloneWorkoutId: "sw1",
                status: .inProgress, startedAt: .now, completedAt: nil, notes: nil
            ))
        )

        let sessionId = await vm.resolveBlockerAndStart(blocker, discard: true)
        #expect(sessionId == "ss-new")
        #expect(vm.blocker == nil)
    }

    @Test("a 409 on start falls back to resuming the server's session")
    func startConflictResumes() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneWorkout(id: "sw1"), response: makeWorkout())
        stubNoProgramWorkout(client)
        // Calls 1 (load) and 2 (pre-check) miss the raced session; call 3 —
        // the refetch after the POST 409s — sees it.
        let empty: [StandaloneSessionListItemDTO] = []
        let raced = [makeListItem(id: "ss-raced", workoutId: "sw1")]
        var activeCalls = 0
        client.handlers["GET /api/standalone-workout-sessions/active"] = { _ in
            activeCalls += 1
            let sessions = activeCalls <= 2 ? empty : raced
            return try JSONCoding.encoder.encode(StandaloneSessionListResponseDTO(sessions: sessions))
        }
        client.handlers["POST /api/standalone-workout-sessions"] = { _ in
            throw APIError.httpError(statusCode: 409, message: "already in progress", data: Data())
        }
        let vm = makeViewModel(client: client)
        await vm.load()

        let sessionId = await vm.startOrResume()
        #expect(sessionId == "ss-raced")
        #expect(vm.activeSessionForThisWorkout?.id == "ss-raced")
    }
}
