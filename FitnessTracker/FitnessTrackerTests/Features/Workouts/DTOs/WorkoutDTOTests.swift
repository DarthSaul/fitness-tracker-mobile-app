import Foundation
import Testing
@testable import FitnessTracker

@Suite("Workout DTOs")
struct WorkoutDTOTests {
    private let decoder = JSONCoding.decoder

    @Test("SessionStatus decodes uppercase raw values")
    func sessionStatusDecodes() throws {
        let inProgress = try decoder.decode(SessionStatus.self, from: #""IN_PROGRESS""#.data(using: .utf8)!)
        let editing = try decoder.decode(SessionStatus.self, from: #""EDITING""#.data(using: .utf8)!)
        let completed = try decoder.decode(SessionStatus.self, from: #""COMPLETED""#.data(using: .utf8)!)

        #expect(inProgress == .inProgress)
        #expect(editing == .editing)
        #expect(completed == .completed)
    }

    @Test("WorkoutSessionDTO decodes with nullable completedAt and notes")
    func workoutSessionDecodes() throws {
        let json = #"""
        {
          "id": "ws1",
          "userId": "u1",
          "userProgramId": "up1",
          "weekNumber": 2,
          "dayNumber": 3,
          "status": "IN_PROGRESS",
          "startedAt": "2026-05-03T18:00:00Z",
          "completedAt": null,
          "notes": null
        }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(WorkoutSessionDTO.self, from: json)

        #expect(dto.id == "ws1")
        #expect(dto.status == .inProgress)
        #expect(dto.weekNumber == 2)
        #expect(dto.completedAt == nil)
        #expect(dto.notes == nil)
    }

    @Test("CompletedSetDTO decodes the three flavors")
    func completedSetThreeFlavors() throws {
        // Template set: exerciseSetId set, programExerciseId nil, adhocExerciseName nil
        let template = #"""
        { "id": "cs1", "workoutSessionId": "ws1", "exerciseSetId": "es1",
          "programExerciseId": null, "adhocExerciseName": null,
          "reps": 5, "weight": 135.0, "rpe": 7.5, "notes": null,
          "completedAt": "2026-05-03T18:05:00Z" }
        """#.data(using: .utf8)!

        // Extra set: exerciseSetId nil, programExerciseId set
        let extra = #"""
        { "id": "cs2", "workoutSessionId": "ws1", "exerciseSetId": null,
          "programExerciseId": "pe1", "adhocExerciseName": null,
          "reps": 8, "weight": 100.0, "rpe": null, "notes": "Felt easy",
          "completedAt": "2026-05-03T18:08:00Z" }
        """#.data(using: .utf8)!

        // Ad-hoc set: both IDs nil, adhocExerciseName set
        let adhoc = #"""
        { "id": "cs3", "workoutSessionId": "ws1", "exerciseSetId": null,
          "programExerciseId": null, "adhocExerciseName": "Calf Raise",
          "reps": null, "weight": null, "rpe": null, "notes": null,
          "completedAt": "2026-05-03T18:12:00Z" }
        """#.data(using: .utf8)!

        let t = try decoder.decode(CompletedSetDTO.self, from: template)
        let e = try decoder.decode(CompletedSetDTO.self, from: extra)
        let a = try decoder.decode(CompletedSetDTO.self, from: adhoc)

        #expect(t.exerciseSetId == "es1" && t.programExerciseId == nil && t.adhocExerciseName == nil)
        #expect(e.exerciseSetId == nil && e.programExerciseId == "pe1" && e.notes == "Felt easy")
        #expect(a.exerciseSetId == nil && a.programExerciseId == nil && a.adhocExerciseName == "Calf Raise")
        #expect(a.reps == nil && a.weight == nil)
    }

    @Test("ActiveProgramSessionDTO decodes _count.completedSets aggregate")
    func activeProgramSessionDecodesCount() throws {
        let json = #"""
        {
          "id": "ws1",
          "userId": "u1",
          "userProgramId": "up1",
          "weekNumber": 1,
          "dayNumber": 1,
          "status": "COMPLETED",
          "startedAt": "2026-05-01T18:00:00Z",
          "completedAt": "2026-05-01T19:00:00Z",
          "notes": null,
          "_count": { "completedSets": 16 }
        }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(ActiveProgramSessionDTO.self, from: json)
        #expect(dto.count.completedSets == 16)
        #expect(dto.status == .completed)
    }
}
