import Foundation
import Testing
@testable import FitnessTracker

@Suite("HomeRepository")
@MainActor
struct HomeRepositoryTests {
    // MARK: - Fixtures
    private func makeActiveProgramDTO(id: String = "up1") -> ActiveUserProgramDTO {
        ActiveUserProgramDTO(
            id: id,
            userId: "u1",
            programId: "p1",
            isActive: true,
            currentWeek: 1,
            currentDay: 1,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            program: ActiveUserProgramDTO.ActiveProgramDetail(
                id: "p1",
                name: "Strength Base",
                description: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                weeks: []
            )
        )
    }

    // MARK: - 200 happy paths

    @Test("fetchActiveUserProgram decodes the active program")
    func fetchActive() async throws {
        let client = MockAPIClient()
        client.stub(.getActiveUserProgram, response: makeActiveProgramDTO())
        let repo = HomeRepository(apiClient: client)

        let dto = try await repo.fetchActiveUserProgram()
        #expect(dto?.id == "up1")
    }

    @Test("fetchActiveProgramSessions unwraps the sessions wrapper")
    func fetchSessions() async throws {
        let client = MockAPIClient()
        let session = ActiveProgramSessionDTO(
            id: "s1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .completed,
            startedAt: .now, completedAt: .now, notes: nil,
            count: ActiveProgramSessionDTO.Count(completedSets: 8)
        )
        client.stub(.getActiveProgramSessions, response: ActiveProgramSessionsResponseDTO(sessions: [session]))
        let repo = HomeRepository(apiClient: client)

        let sessions = try await repo.fetchActiveProgramSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].status == .completed)
    }

    @Test("fetchScheduledWorkouts unwraps the response and filters by program")
    func fetchScheduled() async throws {
        let client = MockAPIClient()
        let scheduled = ScheduledWorkoutDTO(
            id: "sw1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 2,
            scheduledDate: .now, createdAt: .now
        )
        client.stub(
            .getScheduledWorkouts(userProgramId: "up1", from: nil, to: nil),
            response: ScheduledWorkoutsResponseDTO(scheduledWorkouts: [scheduled])
        )
        let repo = HomeRepository(apiClient: client)

        let result = try await repo.fetchScheduledWorkouts(userProgramId: "up1")
        #expect(result.count == 1)
        #expect(result[0].id == "sw1")
    }

    // MARK: - 404 → nil mapping

    @Test("fetchActiveUserProgram returns nil on 404")
    func fetchActiveNotFound() async throws {
        let client = MockAPIClient()
        client.handlers["/api/user-programs/active"] = { _ in
            throw APIError.httpError(statusCode: 404, message: nil, data: Data())
        }
        let repo = HomeRepository(apiClient: client)

        let dto = try await repo.fetchActiveUserProgram()
        #expect(dto == nil)
    }

    @Test("fetchActiveWorkout returns nil on 404")
    func fetchActiveWorkoutNotFound() async throws {
        let client = MockAPIClient()
        client.handlers["/api/workouts/active"] = { _ in
            throw APIError.httpError(statusCode: 404, message: nil, data: Data())
        }
        let repo = HomeRepository(apiClient: client)

        let dto = try await repo.fetchActiveWorkout()
        #expect(dto == nil)
    }

    @Test("fetchActiveProgramSessions returns empty array on 404")
    func fetchSessionsNotFound() async throws {
        let client = MockAPIClient()
        client.handlers["/api/user-programs/active/sessions"] = { _ in
            throw APIError.httpError(statusCode: 404, message: nil, data: Data())
        }
        let repo = HomeRepository(apiClient: client)

        let sessions = try await repo.fetchActiveProgramSessions()
        #expect(sessions.isEmpty)
    }

    // MARK: - Mutations

    @Test("scheduleWorkout posts the body and returns the created record")
    func schedulePosts() async throws {
        let client = MockAPIClient()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduled = ScheduledWorkoutDTO(
            id: "sw-new", userProgramId: "up1",
            weekNumber: 2, dayNumber: 3,
            scheduledDate: fixedDate, createdAt: fixedDate
        )
        client.stub(
            .scheduleWorkout(ScheduleWorkoutBody(
                userProgramId: "up1", weekNumber: 2, dayNumber: 3, scheduledDate: fixedDate
            )),
            response: ScheduleWorkoutResponseDTO(scheduledWorkout: scheduled)
        )
        let repo = HomeRepository(apiClient: client)

        let result = try await repo.scheduleWorkout(
            userProgramId: "up1", weekNumber: 2, dayNumber: 3, scheduledDate: fixedDate
        )
        #expect(result.id == "sw-new")
    }

    @Test("unscheduleWorkout dispatches DELETE")
    func unscheduleHits() async throws {
        let client = MockAPIClient()
        client.stub(.unscheduleWorkout(id: "sw1"), response: ["ok": true])
        let repo = HomeRepository(apiClient: client)

        try await repo.unscheduleWorkout(id: "sw1")
    }

    @Test("startWorkout (no body) returns the created session")
    func startWorkoutNoBody() async throws {
        let client = MockAPIClient()
        let session = WorkoutSessionDTO(
            id: "ws1", userId: "u1", userProgramId: "up1",
            weekNumber: 1, dayNumber: 1, status: .inProgress,
            startedAt: .now, completedAt: nil, notes: nil
        )
        let day = ProgramDayDTO(
            id: "d1", programWeekId: "w1", dayNumber: 1, name: "Day 1",
            warmUp: nil, exerciseGroups: []
        )
        client.stub(.createWorkout(nil), response: StartWorkoutResponseDTO(session: session, day: day))
        let repo = HomeRepository(apiClient: client)

        let result = try await repo.startWorkout()
        #expect(result.session.id == "ws1")
    }
}
