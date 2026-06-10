import Foundation
import Testing
@testable import FitnessTracker

@Suite("LiveWorkoutViewModel")
@MainActor
struct LiveWorkoutViewModelTests {
    // MARK: - Fixtures

    private func makeTemplateSet(_ id: String, setNumber: Int = 1) -> ExerciseSetDTO {
        ExerciseSetDTO(
            id: id, programExerciseId: "pe1", setNumber: setNumber,
            reps: 5, weight: 100, rpe: nil, notes: nil, effortTarget: nil
        )
    }

    private func makeProgramDay() -> ProgramDayDTO {
        let exercise = ProgramExerciseDTO(
            id: "pe1", exerciseGroupId: "g1", exerciseId: "ex1", order: 0,
            exercise: ExerciseDTO(id: "ex1", name: "Bench", description: nil),
            sets: [makeTemplateSet("es1", setNumber: 1), makeTemplateSet("es2", setNumber: 2)]
        )
        let group = ExerciseGroupDTO(
            id: "g1", programDayId: "d1", order: 0,
            type: .standard, restSeconds: 90, exercises: [exercise]
        )
        return ProgramDayDTO(
            id: "d1", programWeekId: "w1", dayNumber: 1,
            name: "Day 1", warmUp: nil, exerciseGroups: [group]
        )
    }

    private func makeCompletedSet(
        id: String,
        exerciseSetId: String? = nil,
        programExerciseId: String? = nil,
        adhocExerciseName: String? = nil,
        reps: Int = 5,
        weight: Double = 100,
        rpe: Double? = nil,
        completedAt: Date = .now
    ) -> CompletedSetDTO {
        CompletedSetDTO(
            id: id, workoutSessionId: "ws1",
            exerciseSetId: exerciseSetId, programExerciseId: programExerciseId,
            adhocExerciseName: adhocExerciseName,
            reps: reps, weight: weight, rpe: rpe, notes: nil,
            completedAt: completedAt
        )
    }

    private func makeActiveResponse(completedSets: [CompletedSetDTO] = []) -> ActiveWorkoutResponseDTO {
        let session = ActiveWorkoutResponseDTO.ActiveWorkoutSession(
            id: "ws1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .inProgress,
            startedAt: .now, completedAt: nil, notes: nil,
            completedSets: completedSets,
            userProgram: UserProgramDTO(
                id: "up1", userId: "u1", programId: "p1", isActive: true,
                currentWeek: 1, currentDay: 1, startedAt: .now
            ),
            workoutExerciseSwaps: []
        )
        return ActiveWorkoutResponseDTO(session: session, day: makeProgramDay())
    }

    /// Each VM gets its own UserDefaults suite so the persisted marked-complete
    /// flags don't leak between tests (or into `.standard`).
    private func makeIsolatedStore() -> MarkedCompleteStore {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return MarkedCompleteStore(defaults: defaults)
    }

    private func makeViewModel(
        client: MockAPIClient = MockAPIClient(),
        store: MarkedCompleteStore? = nil
    ) -> LiveWorkoutViewModel {
        let repo = WorkoutRepository(apiClient: client)
        let session = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        return LiveWorkoutViewModel(
            repository: repo,
            sessionManager: session,
            markedCompleteStore: store ?? makeIsolatedStore()
        )
    }

    // MARK: - Load + bucketing

    @Test("load splits completedSets into template / extra / ad-hoc buckets")
    func loadBuckets() async {
        let client = MockAPIClient()
        let template = makeCompletedSet(id: "cs1", exerciseSetId: "es1")
        let extra = makeCompletedSet(id: "cs2", programExerciseId: "pe1")
        let adhoc = makeCompletedSet(id: "cs3", adhocExerciseName: "Pull-up")
        client.stub(.getActiveWorkout, response: makeActiveResponse(completedSets: [template, extra, adhoc]))

        let vm = makeViewModel(client: client)
        await vm.load()

        #expect(vm.completedByExerciseSetId["es1"]?.id == "cs1")
        #expect(vm.extraSets(forProgramExerciseId: "pe1").count == 1)
        #expect(vm.extraSets(forProgramExerciseId: "pe1")[0].id == "cs2")
        #expect(vm.adhocSets.count == 1)
        #expect(vm.adhocSets[0].adhocExerciseName == "Pull-up")
    }

    @Test("load with no active session leaves session/day nil and no error")
    func loadNoActive() async {
        let client = MockAPIClient()
        client.handlers["GET /api/workouts/active"] = { _ in
            throw APIError.httpError(statusCode: 404, message: nil, data: Data())
        }

        let vm = makeViewModel(client: client)
        await vm.load()

        #expect(vm.session == nil)
        #expect(vm.day == nil)
        #expect(vm.loadError == nil)
    }

    // MARK: - Set logging routing

    @Test("logSet POSTs recordSet for unrecorded template sets")
    func logSetRecord() async {
        let client = MockAPIClient()
        client.stub(.getActiveWorkout, response: makeActiveResponse())
        client.stub(
            .recordSet(workoutId: "ws1", body: RecordSetBody(exerciseSetId: "es1", reps: 6, weight: 110, rpe: nil, notes: nil)),
            response: makeCompletedSet(id: "cs-new", exerciseSetId: "es1", reps: 6, weight: 110)
        )

        let vm = makeViewModel(client: client)
        await vm.load()
        await vm.logSet(exerciseSetId: "es1", reps: 6, weight: 110, rpe: nil, notes: nil)

        #expect(vm.completedByExerciseSetId["es1"]?.id == "cs-new")
    }

    @Test("logSet PATCHes updateSet when a CompletedSet already exists")
    func logSetUpdate() async {
        let client = MockAPIClient()
        let existing = makeCompletedSet(id: "cs1", exerciseSetId: "es1", reps: 5, weight: 100)
        client.stub(.getActiveWorkout, response: makeActiveResponse(completedSets: [existing]))
        client.stub(
            .updateSet(workoutId: "ws1", setId: "cs1", body: UpdateSetBody(reps: 8, weight: 120, rpe: nil, notes: nil)),
            response: makeCompletedSet(id: "cs1", exerciseSetId: "es1", reps: 8, weight: 120)
        )

        let vm = makeViewModel(client: client)
        await vm.load()
        await vm.logSet(exerciseSetId: "es1", reps: 8, weight: 120, rpe: nil, notes: nil)

        #expect(vm.completedByExerciseSetId["es1"]?.reps == 8)
    }

    // MARK: - Extra / ad-hoc

    @Test("addExtraSet appends to the extra-sets bucket for the programExercise")
    func addExtraAppends() async {
        let client = MockAPIClient()
        client.stub(.getActiveWorkout, response: makeActiveResponse())
        client.stub(
            .addExtraSet(workoutId: "ws1", programExerciseId: "pe1", body: AddExtraSetBody(reps: 6, weight: 80, rpe: nil, notes: nil)),
            response: makeCompletedSet(id: "cs-extra", programExerciseId: "pe1", reps: 6, weight: 80)
        )

        let vm = makeViewModel(client: client)
        await vm.load()
        await vm.addExtraSet(programExerciseId: "pe1", reps: 6, weight: 80, rpe: nil, notes: nil)

        #expect(vm.extraSets(forProgramExerciseId: "pe1").count == 1)
        #expect(vm.extraSets(forProgramExerciseId: "pe1")[0].id == "cs-extra")
    }

    @Test("addAdHocExercise appends to the ad-hoc list")
    func addAdHocAppends() async {
        let client = MockAPIClient()
        client.stub(.getActiveWorkout, response: makeActiveResponse())
        client.stub(
            .addAdHocSet(workoutId: "ws1", body: AddAdHocSetBody(exerciseName: "Pull-up")),
            response: makeCompletedSet(id: "cs-adhoc", adhocExerciseName: "Pull-up", reps: 0, weight: 0)
        )

        let vm = makeViewModel(client: client)
        await vm.load()
        await vm.addAdHocExercise(name: "Pull-up")

        #expect(vm.adhocSets.count == 1)
        #expect(vm.adhocSets[0].adhocExerciseName == "Pull-up")
    }

    // MARK: - Complete / abandon

    @Test("completeWorkout returns true on success")
    func completeReturnsTrue() async {
        let client = MockAPIClient()
        client.stub(.getActiveWorkout, response: makeActiveResponse())
        // Path-keyed stub so we don't have to construct an exact body match.
        client.handlers["PATCH /api/workouts/ws1/complete"] = { _ in
            try JSONCoding.encoder.encode(CompleteWorkoutResponseDTO(
                session: WorkoutSessionDTO(
                    id: "ws1", userId: "u1", userProgramId: "up1",
                    weekNumber: 1, dayNumber: 1, status: .completed,
                    startedAt: .now, completedAt: .now, notes: nil
                ),
                userProgram: UserProgramDTO(
                    id: "up1", userId: "u1", programId: "p1", isActive: true,
                    currentWeek: 1, currentDay: 2, startedAt: .now
                ),
                programCompleted: false
            ))
        }

        let vm = makeViewModel(client: client)
        await vm.load()
        let ok = await vm.completeWorkout()
        #expect(ok == true)
    }

    @Test("abandonWorkout clears session/day and returns true")
    func abandonClears() async {
        let client = MockAPIClient()
        client.stub(.getActiveWorkout, response: makeActiveResponse())
        client.stub(.abandonWorkout(id: "ws1"), response: ["deleted": true])

        let vm = makeViewModel(client: client)
        await vm.load()
        #expect(vm.session != nil)
        let ok = await vm.abandonWorkout()

        #expect(ok == true)
        #expect(vm.session == nil)
        #expect(vm.day == nil)
    }

    // MARK: - Mark complete

    @Test("toggleMarkedComplete flips the per-exercise marked-complete flag")
    func toggleMarkedComplete() async throws {
        let client = MockAPIClient()
        client.stub(.getActiveWorkout, response: makeActiveResponse())

        let vm = makeViewModel(client: client)
        await vm.load()

        #expect(vm.isMarkedComplete(programExerciseId: "pe1") == false)
        vm.toggleMarkedComplete(programExerciseId: "pe1")
        #expect(vm.isMarkedComplete(programExerciseId: "pe1") == true)
        vm.toggleMarkedComplete(programExerciseId: "pe1")
        #expect(vm.isMarkedComplete(programExerciseId: "pe1") == false)
    }

    @Test("marked-complete flag persists across a reload via the store")
    func markedCompletePersists() async {
        let store = makeIsolatedStore()
        let client = MockAPIClient()
        client.stub(.getActiveWorkout, response: makeActiveResponse())

        // First VM marks pe1 complete, persisting to the shared store.
        let vm1 = makeViewModel(client: client, store: store)
        await vm1.load()
        vm1.toggleMarkedComplete(programExerciseId: "pe1")

        // A fresh VM backed by the same store should reload the flag on load().
        let vm2 = makeViewModel(client: client, store: store)
        await vm2.load()
        #expect(vm2.isMarkedComplete(programExerciseId: "pe1") == true)
    }

    @Test("completing a workout clears its persisted marked-complete flags")
    func completeClearsMarkedComplete() async {
        let store = makeIsolatedStore()
        let client = MockAPIClient()
        client.stub(.getActiveWorkout, response: makeActiveResponse())
        client.handlers["PATCH /api/workouts/ws1/complete"] = { _ in
            try JSONCoding.encoder.encode(CompleteWorkoutResponseDTO(
                session: WorkoutSessionDTO(
                    id: "ws1", userId: "u1", userProgramId: "up1",
                    weekNumber: 1, dayNumber: 1, status: .completed,
                    startedAt: .now, completedAt: .now, notes: nil
                ),
                userProgram: UserProgramDTO(
                    id: "up1", userId: "u1", programId: "p1", isActive: true,
                    currentWeek: 1, currentDay: 2, startedAt: .now
                ),
                programCompleted: false
            ))
        }

        let vm = makeViewModel(client: client, store: store)
        await vm.load()
        vm.toggleMarkedComplete(programExerciseId: "pe1")
        #expect(store.load(sessionId: "ws1").isEmpty == false)

        _ = await vm.completeWorkout()
        #expect(store.load(sessionId: "ws1").isEmpty == true)
    }

    // MARK: - Most recent logged set ("Copy Previous Weight")

    @Test("mostRecentLoggedSet picks the latest by completedAt across template + extra")
    func mostRecentLoggedSet() async {
        let client = MockAPIClient()
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        // Template set logged earlier; extra set logged later.
        let template = makeCompletedSet(id: "cs1", exerciseSetId: "es1", reps: 5, weight: 100, completedAt: early)
        let extra = makeCompletedSet(id: "cs2", programExerciseId: "pe1", reps: 8, weight: 120, completedAt: late)
        client.stub(.getActiveWorkout, response: makeActiveResponse(completedSets: [template, extra]))

        let vm = makeViewModel(client: client)
        await vm.load()

        let recent = vm.mostRecentLoggedSet(programExerciseId: "pe1", templateSetIds: ["es1", "es2"])
        #expect(recent?.id == "cs2")
        // Weight is what "Copy Previous Weight" pulls from this set.
        #expect(recent?.weight == 120)

        // Excluding the latest falls back to the next most recent.
        let prior = vm.mostRecentLoggedSet(
            programExerciseId: "pe1", templateSetIds: ["es1", "es2"], excludingCompletedSetId: "cs2"
        )
        #expect(prior?.id == "cs1")
    }

    @Test("mostRecentLoggedSet returns nil when nothing is logged for the exercise")
    func mostRecentLoggedSetEmpty() async {
        let client = MockAPIClient()
        client.stub(.getActiveWorkout, response: makeActiveResponse())

        let vm = makeViewModel(client: client)
        await vm.load()

        #expect(vm.mostRecentLoggedSet(programExerciseId: "pe1", templateSetIds: ["es1", "es2"]) == nil)
    }
}
