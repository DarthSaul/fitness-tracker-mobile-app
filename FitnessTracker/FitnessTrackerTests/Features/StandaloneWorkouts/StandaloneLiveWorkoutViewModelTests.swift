import Foundation
import Testing
@testable import FitnessTracker

@Suite("StandaloneLiveWorkoutViewModel")
@MainActor
struct StandaloneLiveWorkoutViewModelTests {
    // MARK: - Fixtures

    private func makeTemplateSet(_ id: String, setNumber: Int = 1) -> StandaloneWorkoutSetDTO {
        StandaloneWorkoutSetDTO(
            id: id, standaloneWorkoutExerciseId: "swe1", setNumber: setNumber,
            reps: 10, weight: 45, rpe: nil, notes: nil, effortTarget: nil
        )
    }

    private func makeWorkout() -> StandaloneWorkoutDetailDTO {
        let exercise = StandaloneWorkoutExerciseDTO(
            id: "swe1", groupId: "g1", exerciseId: "ex1", order: 1,
            exercise: ExerciseDTO(id: "ex1", name: "Goblet Squat", description: nil),
            sets: [makeTemplateSet("sws1", setNumber: 1), makeTemplateSet("sws2", setNumber: 2)]
        )
        let group = StandaloneWorkoutGroupDTO(
            id: "g1", standaloneWorkoutId: "sw1", order: 1,
            type: .standard, label: nil, restSeconds: 60, exercises: [exercise]
        )
        return StandaloneWorkoutDetailDTO(
            id: "sw1", category: "KB Only", order: 1, name: nil,
            description: nil, createdAt: .now, groups: [group]
        )
    }

    private func makeCompletedSet(
        id: String,
        standaloneWorkoutSetId: String? = nil,
        adhocExerciseName: String? = nil,
        reps: Int = 10,
        completedAt: Date = .now
    ) -> StandaloneCompletedSetDTO {
        StandaloneCompletedSetDTO(
            id: id, standaloneWorkoutSessionId: "ss1",
            standaloneWorkoutSetId: standaloneWorkoutSetId,
            adhocExerciseName: adhocExerciseName,
            reps: reps, weight: 45, rpe: nil, notes: nil, completedAt: completedAt
        )
    }

    private func makeDetailResponse(completedSets: [StandaloneCompletedSetDTO] = []) -> StandaloneSessionDetailResponseDTO {
        StandaloneSessionDetailResponseDTO(
            session: StandaloneSessionDetailResponseDTO.SessionWithSets(
                id: "ss1", userId: "u1", standaloneWorkoutId: "sw1",
                status: .inProgress, startedAt: .now, completedAt: nil, notes: nil,
                completedSets: completedSets
            ),
            workout: makeWorkout()
        )
    }

    /// Each VM gets its own UserDefaults suite so the persisted marked-complete
    /// flags don't leak between tests (or into `.standard`).
    private func makeIsolatedStore() -> MarkedCompleteStore {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return MarkedCompleteStore(defaults: defaults)
    }

    private func makeViewModel(client: MockAPIClient = MockAPIClient()) -> StandaloneLiveWorkoutViewModel {
        StandaloneLiveWorkoutViewModel(
            sessionId: "ss1",
            repository: StandaloneWorkoutRepository(apiClient: client),
            sessionManager: SessionManager(keychain: KeychainService(), tokenStore: TokenStore()),
            markedCompleteStore: makeIsolatedStore()
        )
    }

    // MARK: - Load / buckets

    @Test("load buckets prescribed and ad-hoc sets separately")
    func loadBuckets() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneSession(id: "ss1"), response: makeDetailResponse(completedSets: [
            makeCompletedSet(id: "cs1", standaloneWorkoutSetId: "sws1"),
            makeCompletedSet(id: "cs2", adhocExerciseName: "Goblet Squat"),
            makeCompletedSet(id: "cs3", adhocExerciseName: "Farmer Carry")
        ]))
        let vm = makeViewModel(client: client)

        await vm.load()

        #expect(vm.completedSet(forTemplateSetId: "sws1")?.id == "cs1")
        #expect(vm.completedSet(forTemplateSetId: "sws2") == nil)
        #expect(vm.loggedTemplateSetCount == 1)
        #expect(vm.totalTemplateSets == 2)
        // Same-named ad-hoc sets render under the exercise card; others in the Ad-hoc section.
        #expect(vm.extraSets(forExerciseName: "Goblet Squat").map(\.id) == ["cs2"])
        #expect(vm.unmatchedAdhocSets.map(\.id) == ["cs3"])
    }

    // MARK: - Set logging

    @Test("logSet records when unlogged and updates when already logged")
    func logSetRoutes() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneSession(id: "ss1"), response: makeDetailResponse())
        client.stub(
            .recordStandaloneSet(sessionId: "ss1", body: .prescribed(standaloneWorkoutSetId: "sws1", reps: 10, weight: 45, rpe: nil, notes: nil)),
            response: makeCompletedSet(id: "cs1", standaloneWorkoutSetId: "sws1")
        )
        let vm = makeViewModel(client: client)
        await vm.load()

        #expect(await vm.logSet(templateSetId: "sws1", reps: 10, weight: 45, rpe: nil, notes: nil))
        #expect(vm.completedSet(forTemplateSetId: "sws1")?.id == "cs1")

        // Second save on the same template set routes to PATCH with the completed-set id.
        client.stub(
            .updateStandaloneSet(sessionId: "ss1", setId: "cs1", body: UpdateSetBody(reps: 12, weight: 45, rpe: nil, notes: nil)),
            response: makeCompletedSet(id: "cs1", standaloneWorkoutSetId: "sws1", reps: 12)
        )
        #expect(await vm.logSet(templateSetId: "sws1", reps: 12, weight: 45, rpe: nil, notes: nil))
        #expect(vm.completedSet(forTemplateSetId: "sws1")?.reps == 12)
    }

    @Test("logSet treats a 409 (already recorded) as success and reloads")
    func logSetConflictIdempotent() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneSession(id: "ss1"), response: makeDetailResponse())
        let vm = makeViewModel(client: client)
        await vm.load()

        client.handlers["POST /api/standalone-workout-sessions/ss1/sets"] = { _ in
            throw APIError.httpError(statusCode: 409, message: "already recorded", data: Data())
        }
        // The reload after the 409 picks up the server's completed set.
        client.stub(.getStandaloneSession(id: "ss1"), response: makeDetailResponse(completedSets: [
            makeCompletedSet(id: "cs1", standaloneWorkoutSetId: "sws1")
        ]))

        #expect(await vm.logSet(templateSetId: "sws1", reps: 10, weight: 45, rpe: nil, notes: nil))
        #expect(vm.completedSet(forTemplateSetId: "sws1")?.id == "cs1")
        #expect(vm.actionError == nil)
    }

    @Test("deleteLoggedSet unmarks the row and treats 404 as already gone")
    func deleteLoggedSet() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneSession(id: "ss1"), response: makeDetailResponse(completedSets: [
            makeCompletedSet(id: "cs1", standaloneWorkoutSetId: "sws1")
        ]))
        let vm = makeViewModel(client: client)
        await vm.load()

        client.handlers["DELETE /api/standalone-workout-sessions/ss1/sets/cs1"] = { _ in
            throw APIError.httpError(statusCode: 404, message: nil, data: Data())
        }

        #expect(await vm.deleteLoggedSet(templateSetId: "sws1"))
        #expect(vm.completedSet(forTemplateSetId: "sws1") == nil)
    }

    // MARK: - Ad-hoc

    @Test("addExtraSet logs an ad-hoc set under the exercise's name")
    func addExtraSet() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneSession(id: "ss1"), response: makeDetailResponse())
        client.stub(
            .recordStandaloneSet(sessionId: "ss1", body: .adhoc(exerciseName: "Goblet Squat", reps: 8, weight: 45, rpe: nil, notes: nil)),
            response: makeCompletedSet(id: "cs9", adhocExerciseName: "Goblet Squat", reps: 8)
        )
        let vm = makeViewModel(client: client)
        await vm.load()

        #expect(await vm.addExtraSet(exerciseName: "Goblet Squat", reps: 8, weight: 45, rpe: nil, notes: nil))
        #expect(vm.extraSets(forExerciseName: "Goblet Squat").map(\.id) == ["cs9"])
        #expect(vm.unmatchedAdhocSets.isEmpty)
    }

    // MARK: - Finalize / discard

    @Test("completeWorkout treats an already-completed 409 as success")
    func completeConflictIdempotent() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneSession(id: "ss1"), response: makeDetailResponse())
        client.handlers["PATCH /api/standalone-workout-sessions/ss1/complete"] = { _ in
            throw APIError.httpError(statusCode: 409, message: "Session already completed", data: Data())
        }
        let vm = makeViewModel(client: client)
        await vm.load()

        #expect(await vm.completeWorkout())
        #expect(vm.actionError == nil)
    }

    @Test("abandonWorkout treats an already-deleted 404 as success")
    func abandonGoneIdempotent() async throws {
        let client = MockAPIClient()
        client.stub(.getStandaloneSession(id: "ss1"), response: makeDetailResponse())
        client.handlers["DELETE /api/standalone-workout-sessions/ss1"] = { _ in
            throw APIError.httpError(statusCode: 404, message: nil, data: Data())
        }
        let vm = makeViewModel(client: client)
        await vm.load()

        #expect(await vm.abandonWorkout())
        #expect(vm.actionError == nil)
    }
}
