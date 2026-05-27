import Foundation
import Testing
@testable import FitnessTracker

@Suite("WorkoutRepository")
@MainActor
struct WorkoutRepositoryTests {
    // MARK: - Fixtures

    private func makeWorkoutSessionDTO(id: String = "ws1", status: SessionStatus = .editing) -> WorkoutSessionDTO {
        WorkoutSessionDTO(
            id: id, userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: status,
            startedAt: .now, completedAt: nil, notes: nil
        )
    }

    private func makeProgramDayDTO() -> ProgramDayDTO {
        ProgramDayDTO(
            id: "d1", programWeekId: "w1", dayNumber: 1,
            name: "Day 1", warmUp: nil, exerciseGroups: []
        )
    }

    private func makeCompletedSetDTO(id: String = "cs1") -> CompletedSetDTO {
        CompletedSetDTO(
            id: id, workoutSessionId: "ws1",
            exerciseSetId: "es1", programExerciseId: nil, adhocExerciseName: nil,
            reps: 5, weight: 135, rpe: 7.5, notes: nil,
            completedAt: .now
        )
    }

    // MARK: - Create / fetch

    @Test("createRetroactiveWorkout posts week+day and decodes session+day")
    func createRetroactive() async throws {
        let client = MockAPIClient()
        client.stub(
            .createWorkout(CreateWorkoutBody(weekNumber: 2, dayNumber: 3)),
            response: StartWorkoutResponseDTO(session: makeWorkoutSessionDTO(), day: makeProgramDayDTO())
        )
        let repo = WorkoutRepository(apiClient: client)

        let response = try await repo.createRetroactiveWorkout(weekNumber: 2, dayNumber: 3)
        #expect(response.session.id == "ws1")
        #expect(response.session.status == .editing)
    }

    @Test("getWorkout decodes the same shape as /active")
    func getWorkoutDecodes() async throws {
        let client = MockAPIClient()
        let session = ActiveWorkoutResponseDTO.ActiveWorkoutSession(
            id: "ws1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .editing,
            startedAt: .now, completedAt: nil, notes: nil,
            completedSets: [makeCompletedSetDTO()],
            userProgram: UserProgramDTO(
                id: "up1", userId: "u1", programId: "p1", isActive: true,
                currentWeek: 1, currentDay: 1, startedAt: .now
            ),
            workoutExerciseSwaps: []
        )
        client.stub(.getWorkout(id: "ws1"), response: ActiveWorkoutResponseDTO(session: session, day: makeProgramDayDTO()))
        let repo = WorkoutRepository(apiClient: client)

        let response = try await repo.getWorkout(id: "ws1")
        #expect(response.session.id == "ws1")
        #expect(response.session.completedSets.count == 1)
    }

    // MARK: - Set logging

    @Test("recordSet posts and decodes the new completed set")
    func recordSetDispatch() async throws {
        let client = MockAPIClient()
        let body = RecordSetBody(exerciseSetId: "es1", reps: 5, weight: 135, rpe: nil, notes: nil)
        client.stub(.recordSet(workoutId: "ws1", body: body), response: makeCompletedSetDTO())
        let repo = WorkoutRepository(apiClient: client)

        let result = try await repo.recordSet(workoutId: "ws1", body: body)
        #expect(result.id == "cs1")
    }

    @Test("updateSet patches and decodes the updated record")
    func updateSetDispatch() async throws {
        let client = MockAPIClient()
        let body = UpdateSetBody(reps: 8, weight: 145, rpe: 8, notes: "felt good")
        client.stub(.updateSet(workoutId: "ws1", setId: "cs1", body: body), response: makeCompletedSetDTO(id: "cs1"))
        let repo = WorkoutRepository(apiClient: client)

        let result = try await repo.updateSet(workoutId: "ws1", setId: "cs1", body: body)
        #expect(result.id == "cs1")
    }

    @Test("deleteSet dispatches and ignores the response body")
    func deleteSetDispatch() async throws {
        let client = MockAPIClient()
        client.stub(.deleteSet(workoutId: "ws1", setId: "cs1"), response: ["deleted": true])
        let repo = WorkoutRepository(apiClient: client)

        try await repo.deleteSet(workoutId: "ws1", setId: "cs1")
    }

    // MARK: - Finalize / discard

    @Test("completeWorkout sends the backdated date in the body")
    func completeWithBackdate() async throws {
        let client = MockAPIClient()
        let backdated = Date(timeIntervalSince1970: 1_700_000_000)
        client.stub(
            .completeWorkout(id: "ws1", body: CompleteWorkoutBody(completedAt: backdated)),
            response: CompleteWorkoutResponseDTO(
                session: makeWorkoutSessionDTO(status: .completed),
                userProgram: UserProgramDTO(
                    id: "up1", userId: "u1", programId: "p1", isActive: true,
                    currentWeek: 1, currentDay: 2, startedAt: .now
                ),
                programCompleted: false
            )
        )
        let repo = WorkoutRepository(apiClient: client)

        let response = try await repo.completeWorkout(id: "ws1", completedAt: backdated)
        #expect(response.session.status == .completed)
        #expect(response.programCompleted == false)
    }

    @Test("abandonWorkout dispatches DELETE")
    func abandonDispatch() async throws {
        let client = MockAPIClient()
        client.stub(.abandonWorkout(id: "ws1"), response: ["deleted": true])
        let repo = WorkoutRepository(apiClient: client)

        try await repo.abandonWorkout(id: "ws1")
    }

    // MARK: - getActiveWorkout (M7)

    @Test("getActiveWorkout returns the response on 200")
    func getActiveWorkoutFound() async throws {
        let client = MockAPIClient()
        let session = ActiveWorkoutResponseDTO.ActiveWorkoutSession(
            id: "ws1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .inProgress,
            startedAt: .now, completedAt: nil, notes: nil,
            completedSets: [], userProgram: UserProgramDTO(
                id: "up1", userId: "u1", programId: "p1", isActive: true,
                currentWeek: 1, currentDay: 1, startedAt: .now
            ),
            workoutExerciseSwaps: []
        )
        client.stub(.getActiveWorkout, response: ActiveWorkoutResponseDTO(session: session, day: makeProgramDayDTO()))
        let repo = WorkoutRepository(apiClient: client)

        let result = try await repo.getActiveWorkout()
        #expect(result?.session.id == "ws1")
    }

    @Test("getActiveWorkout returns nil on 404")
    func getActiveWorkoutNotFound() async throws {
        let client = MockAPIClient()
        client.handlers["GET /api/workouts/active"] = { _ in
            throw APIError.httpError(statusCode: 404, message: nil, data: Data())
        }
        let repo = WorkoutRepository(apiClient: client)

        let result = try await repo.getActiveWorkout()
        #expect(result == nil)
    }

    // MARK: - Extra sets / ad-hoc / swap / notes (M7)

    @Test("addExtraSet posts to the programExercise extra-sets endpoint")
    func addExtraSetDispatch() async throws {
        let client = MockAPIClient()
        let body = AddExtraSetBody(reps: 8, weight: 100, rpe: nil, notes: nil)
        client.stub(.addExtraSet(workoutId: "ws1", programExerciseId: "pe1", body: body), response: makeCompletedSetDTO(id: "cs-extra"))
        let repo = WorkoutRepository(apiClient: client)

        let result = try await repo.addExtraSet(workoutId: "ws1", programExerciseId: "pe1", body: body)
        #expect(result.id == "cs-extra")
    }

    @Test("deleteExtraSet hits the extra-sets DELETE endpoint")
    func deleteExtraSetDispatch() async throws {
        let client = MockAPIClient()
        client.stub(.deleteExtraSet(workoutId: "ws1", completedSetId: "cs-extra"), response: ["deleted": true])
        let repo = WorkoutRepository(apiClient: client)

        try await repo.deleteExtraSet(workoutId: "ws1", completedSetId: "cs-extra")
    }

    @Test("swapExercise posts the replacement and decodes deletedSetCount")
    func swapDispatch() async throws {
        let client = MockAPIClient()
        let swap = WorkoutExerciseSwapDTO(
            id: "swap1", workoutSessionId: "ws1", programExerciseId: "pe1",
            originalExerciseId: "ex-orig", replacementExerciseId: "ex-new",
            createdAt: .now
        )
        client.stub(
            .swapExercise(workoutId: "ws1", programExerciseId: "pe1", body: SwapExerciseBody(replacementExerciseId: "ex-new")),
            response: SwapExerciseResponseDTO(swap: swap, deletedSetCount: 3)
        )
        let repo = WorkoutRepository(apiClient: client)

        let result = try await repo.swapExercise(workoutId: "ws1", programExerciseId: "pe1", replacementExerciseId: "ex-new")
        #expect(result.swap.replacementExerciseId == "ex-new")
        #expect(result.deletedSetCount == 3)
    }

    @Test("addAdHocSet posts the exercise name and decodes the new completed set")
    func addAdHocDispatch() async throws {
        let client = MockAPIClient()
        client.stub(
            .addAdHocSet(workoutId: "ws1", body: AddAdHocSetBody(exerciseName: "Pull-up")),
            response: CompletedSetDTO(
                id: "cs-adhoc", workoutSessionId: "ws1",
                exerciseSetId: nil, programExerciseId: nil, adhocExerciseName: "Pull-up",
                reps: nil, weight: nil, rpe: nil, notes: nil, completedAt: .now
            )
        )
        let repo = WorkoutRepository(apiClient: client)

        let result = try await repo.addAdHocSet(workoutId: "ws1", exerciseName: "Pull-up")
        #expect(result.adhocExerciseName == "Pull-up")
    }

    @Test("updateNotes patches and decodes the {id, notes, completedAt} response")
    func updateNotesDispatch() async throws {
        let client = MockAPIClient()
        client.stub(
            .updateWorkoutNotes(id: "ws1", body: UpdateWorkoutNotesBody(notes: "felt strong today")),
            response: UpdateWorkoutResponseDTO(id: "ws1", notes: "felt strong today", completedAt: nil)
        )
        let repo = WorkoutRepository(apiClient: client)

        let result = try await repo.updateNotes(workoutId: "ws1", notes: "felt strong today")
        #expect(result.notes == "felt strong today")
    }

    @Test("updateWorkoutDate patches /api/workouts/:id with the new completedAt")
    func updateWorkoutDateDispatch() async throws {
        let client = MockAPIClient()
        let newDate = Date(timeIntervalSince1970: 1_716_206_400) // 2024-05-20T12:00:00Z, arbitrary fixed point
        client.stub(
            .updateWorkoutDate(id: "ws1", body: UpdateWorkoutDateBody(completedAt: newDate)),
            response: UpdateWorkoutResponseDTO(id: "ws1", notes: nil, completedAt: newDate)
        )
        let repo = WorkoutRepository(apiClient: client)

        let result = try await repo.updateWorkoutDate(id: "ws1", completedAt: newDate)
        #expect(result.completedAt == newDate)
    }
}
