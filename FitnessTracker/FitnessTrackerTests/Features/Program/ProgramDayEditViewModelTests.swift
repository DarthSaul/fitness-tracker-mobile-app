import Foundation
import Testing
@testable import FitnessTracker

@Suite("ProgramDayEditViewModel")
@MainActor
struct ProgramDayEditViewModelTests {
    // MARK: - Fixtures

    private func makeTemplateSet(_ id: String, setNumber: Int = 1) -> ExerciseSetDTO {
        ExerciseSetDTO(
            id: id, programExerciseId: "pe1", setNumber: setNumber,
            reps: 5, weight: 100, rpe: nil, notes: nil, effortTarget: nil
        )
    }

    private func makeProgramDay(setIds: [String] = ["es1", "es2"]) -> ProgramDayDTO {
        let exercise = ProgramExerciseDTO(
            id: "pe1", exerciseGroupId: "g1", exerciseId: "ex1", order: 0,
            exercise: ExerciseDTO(id: "ex1", name: "Bench", description: nil),
            sets: setIds.enumerated().map { i, id in makeTemplateSet(id, setNumber: i + 1) }
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

    private func makeCompletedSet(id: String, exerciseSetId: String, reps: Int = 5, weight: Double = 100) -> CompletedSetDTO {
        CompletedSetDTO(
            id: id, workoutSessionId: "ws1",
            exerciseSetId: exerciseSetId, programExerciseId: nil, adhocExerciseName: nil,
            reps: reps, weight: weight, rpe: nil, notes: nil,
            completedAt: .now
        )
    }

    private func makeViewModel(
        client: MockAPIClient = MockAPIClient(),
        existingSessionId: String? = nil,
        onChange: @escaping () -> Void = {}
    ) -> ProgramDayEditViewModel {
        let repo = WorkoutRepository(apiClient: client)
        return ProgramDayEditViewModel(
            weekNumber: 1,
            day: makeProgramDay(),
            existingSessionId: existingSessionId,
            repository: repo,
            onChange: onChange
        )
    }

    // MARK: - loadIfNeeded

    @Test("loadIfNeeded fetches existing session and builds the completed map")
    func loadExisting() async throws {
        let client = MockAPIClient()
        let session = ActiveWorkoutResponseDTO.ActiveWorkoutSession(
            id: "ws1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .editing,
            startedAt: .now, completedAt: nil, notes: nil,
            completedSets: [makeCompletedSet(id: "cs1", exerciseSetId: "es1", reps: 8, weight: 110)],
            userProgram: UserProgramDTO(
                id: "up1", userId: "u1", programId: "p1", isActive: true,
                currentWeek: 1, currentDay: 1, startedAt: .now
            ),
            workoutExerciseSwaps: []
        )
        client.stub(.getWorkout(id: "ws1"), response: ActiveWorkoutResponseDTO(session: session, day: makeProgramDay()))

        let vm = makeViewModel(client: client, existingSessionId: "ws1")
        await vm.loadIfNeeded()

        #expect(vm.session?.id == "ws1")
        #expect(vm.completedSet(forExerciseSetId: "es1")?.reps == 8)
        #expect(vm.completedSet(forExerciseSetId: "es2") == nil)
    }

    @Test("loadIfNeeded is a no-op when no existing session id")
    func loadNoExisting() async throws {
        let vm = makeViewModel(client: MockAPIClient(), existingSessionId: nil)
        await vm.loadIfNeeded()
        #expect(vm.session == nil)
    }

    // MARK: - startRetroactive

    @Test("startRetroactive POSTs and seeds an empty session in memory")
    func startRetroactiveCreates() async throws {
        let client = MockAPIClient()
        let session = WorkoutSessionDTO(
            id: "ws-new", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .editing,
            startedAt: .now, completedAt: nil, notes: nil
        )
        client.stub(
            .createWorkout(CreateWorkoutBody(weekNumber: 1, dayNumber: 1)),
            response: StartWorkoutResponseDTO(session: session, day: makeProgramDay())
        )

        var changeCount = 0
        let vm = makeViewModel(client: client, onChange: { changeCount += 1 })

        await vm.startRetroactive()

        #expect(vm.session?.id == "ws-new")
        #expect(vm.completedByExerciseSetId.isEmpty)
        #expect(changeCount == 1)
    }

    // MARK: - logSet routing

    @Test("logSet POSTs to recordSet when no existing CompletedSet for the template")
    func logSetRoutesToRecord() async throws {
        let client = MockAPIClient()
        let session = WorkoutSessionDTO(
            id: "ws1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .editing,
            startedAt: .now, completedAt: nil, notes: nil
        )
        client.stub(
            .createWorkout(CreateWorkoutBody(weekNumber: 1, dayNumber: 1)),
            response: StartWorkoutResponseDTO(session: session, day: makeProgramDay())
        )
        client.stub(
            .recordSet(workoutId: "ws1", body: RecordSetBody(
                exerciseSetId: "es1", reps: 5, weight: 135, rpe: nil, notes: nil
            )),
            response: makeCompletedSet(id: "cs-new", exerciseSetId: "es1", reps: 5, weight: 135)
        )

        let vm = makeViewModel(client: client)
        await vm.startRetroactive()
        await vm.logSet(exerciseSetId: "es1", reps: 5, weight: 135, rpe: nil, notes: nil)

        #expect(vm.completedSet(forExerciseSetId: "es1")?.id == "cs-new")
        #expect(vm.actionError == nil)
    }

    @Test("logSet PATCHes updateSet when a CompletedSet already exists")
    func logSetRoutesToUpdate() async throws {
        let client = MockAPIClient()
        let existing = makeCompletedSet(id: "cs1", exerciseSetId: "es1", reps: 5, weight: 100)
        let session = ActiveWorkoutResponseDTO.ActiveWorkoutSession(
            id: "ws1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .editing,
            startedAt: .now, completedAt: nil, notes: nil,
            completedSets: [existing],
            userProgram: UserProgramDTO(
                id: "up1", userId: "u1", programId: "p1", isActive: true,
                currentWeek: 1, currentDay: 1, startedAt: .now
            ),
            workoutExerciseSwaps: []
        )
        client.stub(.getWorkout(id: "ws1"), response: ActiveWorkoutResponseDTO(session: session, day: makeProgramDay()))
        client.stub(
            .updateSet(workoutId: "ws1", setId: "cs1", body: UpdateSetBody(
                reps: 8, weight: 110, rpe: nil, notes: nil
            )),
            response: makeCompletedSet(id: "cs1", exerciseSetId: "es1", reps: 8, weight: 110)
        )

        let vm = makeViewModel(client: client, existingSessionId: "ws1")
        await vm.loadIfNeeded()
        await vm.logSet(exerciseSetId: "es1", reps: 8, weight: 110, rpe: nil, notes: nil)

        #expect(vm.completedSet(forExerciseSetId: "es1")?.reps == 8)
    }

    // MARK: - delete

    @Test("deleteLoggedSet removes the entry and DELETEs server-side")
    func deleteLoggedRemoves() async throws {
        let client = MockAPIClient()
        let existing = makeCompletedSet(id: "cs1", exerciseSetId: "es1")
        let session = ActiveWorkoutResponseDTO.ActiveWorkoutSession(
            id: "ws1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .editing,
            startedAt: .now, completedAt: nil, notes: nil,
            completedSets: [existing],
            userProgram: UserProgramDTO(
                id: "up1", userId: "u1", programId: "p1", isActive: true,
                currentWeek: 1, currentDay: 1, startedAt: .now
            ),
            workoutExerciseSwaps: []
        )
        client.stub(.getWorkout(id: "ws1"), response: ActiveWorkoutResponseDTO(session: session, day: makeProgramDay()))
        client.stub(.deleteSet(workoutId: "ws1", setId: "cs1"), response: ["deleted": true])

        let vm = makeViewModel(client: client, existingSessionId: "ws1")
        await vm.loadIfNeeded()
        #expect(vm.completedSet(forExerciseSetId: "es1") != nil)

        await vm.deleteLoggedSet(exerciseSetId: "es1")
        #expect(vm.completedSet(forExerciseSetId: "es1") == nil)
    }

    // MARK: - completeWithBackdate / discard

    @Test("completeWithBackdate succeeds and reports true")
    func completeReturnsTrue() async throws {
        let client = MockAPIClient()
        let session = WorkoutSessionDTO(
            id: "ws1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .editing,
            startedAt: .now, completedAt: nil, notes: nil
        )
        client.stub(
            .createWorkout(CreateWorkoutBody(weekNumber: 1, dayNumber: 1)),
            response: StartWorkoutResponseDTO(session: session, day: makeProgramDay())
        )
        // The test stub is path-based, so any completedAt value will match.
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
        await vm.startRetroactive()
        let ok = await vm.completeWithBackdate()
        #expect(ok == true)
    }

    @Test("discard succeeds, clears local state, reports true")
    func discardClears() async throws {
        let client = MockAPIClient()
        let session = WorkoutSessionDTO(
            id: "ws1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .editing,
            startedAt: .now, completedAt: nil, notes: nil
        )
        client.stub(
            .createWorkout(CreateWorkoutBody(weekNumber: 1, dayNumber: 1)),
            response: StartWorkoutResponseDTO(session: session, day: makeProgramDay())
        )
        client.stub(.abandonWorkout(id: "ws1"), response: ["deleted": true])

        let vm = makeViewModel(client: client)
        await vm.startRetroactive()
        #expect(vm.session != nil)

        let ok = await vm.discard()
        #expect(ok == true)
        #expect(vm.session == nil)
    }
}
