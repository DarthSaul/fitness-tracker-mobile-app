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
}
