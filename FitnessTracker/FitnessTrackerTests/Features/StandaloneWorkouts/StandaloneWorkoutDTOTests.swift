import Foundation
import Testing
@testable import FitnessTracker

@Suite("StandaloneWorkout DTOs")
struct StandaloneWorkoutDTOTests {
    private let decoder = JSONCoding.decoder

    @Test("catalog decodes a raw array with _count and null name")
    func catalogDecodes() throws {
        let json = #"""
        [
          { "id": "sw1", "category": "Upper Push", "order": 1, "name": null,
            "description": "Push day on the road", "createdAt": "2026-07-01T12:00:00Z",
            "_count": { "groups": 3 } },
          { "id": "sw2", "category": "Upper Push", "order": 2, "name": "Hotel Push",
            "description": null, "createdAt": "2026-07-01T12:00:00Z",
            "_count": { "groups": 4 } }
        ]
        """#.data(using: .utf8)!

        let workouts = try decoder.decode([StandaloneWorkoutSummaryDTO].self, from: json)

        #expect(workouts.count == 2)
        #expect(workouts[0].count.groups == 3)
        #expect(workouts[0].displayName == "Upper Push #1")
        #expect(workouts[1].displayName == "Hotel Push")
    }

    @Test("detail decodes full nesting including group label and effort target")
    func detailDecodes() throws {
        let json = #"""
        { "id": "sw1", "category": "DB Only", "order": 2, "name": null, "description": null,
          "createdAt": "2026-07-01T12:00:00Z",
          "groups": [{ "id": "g1", "standaloneWorkoutId": "sw1", "order": 1,
            "type": "SUPERSET", "label": "Cardio", "restSeconds": 60,
            "exercises": [{ "id": "swe1", "groupId": "g1", "exerciseId": "ex1", "order": 1,
              "exercise": { "id": "ex1", "name": "DB Bench", "description": null,
                            "isCore": false, "videoUrl": null, "animationUrl": null },
              "sets": [{ "id": "sws1", "standaloneWorkoutExerciseId": "swe1",
                         "setNumber": 1, "reps": 10, "weight": null, "rpe": null,
                         "notes": null, "effortTarget": "RPE 7" }] }] }] }
        """#.data(using: .utf8)!

        let workout = try decoder.decode(StandaloneWorkoutDetailDTO.self, from: json)

        #expect(workout.displayName == "DB Only #2")
        #expect(workout.groups.count == 1)
        #expect(workout.groups[0].type == .superset)
        #expect(workout.groups[0].label == "Cardio")
        #expect(workout.groups[0].exercises[0].exercise.name == "DB Bench")
        #expect(workout.groups[0].exercises[0].sets[0].effortTarget == "RPE 7")
    }

    @Test("session list item decodes _count and workout ref")
    func listItemDecodes() throws {
        let json = #"""
        { "sessions": [{ "id": "ss1", "userId": "u1", "standaloneWorkoutId": "sw1",
          "status": "IN_PROGRESS", "startedAt": "2026-07-20T10:00:00Z",
          "completedAt": null, "notes": null,
          "_count": { "completedSets": 4 },
          "standaloneWorkout": { "id": "sw1", "category": "KB Only", "order": 3, "name": null } }] }
        """#.data(using: .utf8)!

        let response = try decoder.decode(StandaloneSessionListResponseDTO.self, from: json)

        #expect(response.sessions.count == 1)
        #expect(response.sessions[0].count.completedSets == 4)
        #expect(response.sessions[0].status == .inProgress)
        #expect(response.sessions[0].standaloneWorkout.displayName == "KB Only #3")
    }

    @Test("completed set decodes both flavors")
    func completedSetFlavors() throws {
        let prescribed = #"""
        { "id": "cs1", "standaloneWorkoutSessionId": "ss1", "standaloneWorkoutSetId": "sws1",
          "adhocExerciseName": null, "reps": 10, "weight": 45.5, "rpe": null,
          "notes": null, "completedAt": "2026-07-20T10:05:00Z" }
        """#.data(using: .utf8)!

        let adhoc = #"""
        { "id": "cs2", "standaloneWorkoutSessionId": "ss1", "standaloneWorkoutSetId": null,
          "adhocExerciseName": "Farmer Carry", "reps": null, "weight": null, "rpe": 8,
          "notes": "heavy", "completedAt": "2026-07-20T10:10:00Z" }
        """#.data(using: .utf8)!

        let p = try decoder.decode(StandaloneCompletedSetDTO.self, from: prescribed)
        let a = try decoder.decode(StandaloneCompletedSetDTO.self, from: adhoc)

        #expect(p.standaloneWorkoutSetId == "sws1")
        #expect(p.adhocExerciseName == nil)
        #expect(p.weight == 45.5)
        #expect(a.standaloneWorkoutSetId == nil)
        #expect(a.adhocExerciseName == "Farmer Carry")
        #expect(a.rpe == 8)
    }

    @Test("session detail decodes session with sets plus workout template")
    func sessionDetailDecodes() throws {
        let json = #"""
        { "session": { "id": "ss1", "userId": "u1", "standaloneWorkoutId": "sw1",
            "status": "COMPLETED", "startedAt": "2026-07-20T10:00:00Z",
            "completedAt": "2026-07-20T10:40:00Z", "notes": null,
            "completedSets": [{ "id": "cs1", "standaloneWorkoutSessionId": "ss1",
              "standaloneWorkoutSetId": "sws1", "adhocExerciseName": null,
              "reps": 10, "weight": null, "rpe": null, "notes": null,
              "completedAt": "2026-07-20T10:05:00Z" }] },
          "workout": { "id": "sw1", "category": "Total Body", "order": 1, "name": null,
            "description": null, "createdAt": "2026-07-01T12:00:00Z", "groups": [] } }
        """#.data(using: .utf8)!

        let response = try decoder.decode(StandaloneSessionDetailResponseDTO.self, from: json)

        #expect(response.session.status == .completed)
        #expect(response.session.completedSets.count == 1)
        #expect(response.workout.displayName == "Total Body #1")
    }

    @Test("RecordStandaloneSetBody omits the unused discriminator on the wire")
    func recordBodyDiscriminator() throws {
        let prescribed = try JSONCoding.encoder.encode(
            RecordStandaloneSetBody.prescribed(standaloneWorkoutSetId: "sws1", reps: 10, weight: nil, rpe: nil, notes: nil)
        )
        let adhoc = try JSONCoding.encoder.encode(
            RecordStandaloneSetBody.adhoc(exerciseName: "Farmer Carry", reps: nil, weight: nil, rpe: 8, notes: nil)
        )

        let prescribedJSON = try #require(try JSONSerialization.jsonObject(with: prescribed) as? [String: Any])
        let adhocJSON = try #require(try JSONSerialization.jsonObject(with: adhoc) as? [String: Any])

        #expect(prescribedJSON["standaloneWorkoutSetId"] as? String == "sws1")
        #expect(prescribedJSON["adhocExerciseName"] == nil)
        #expect(adhocJSON["adhocExerciseName"] as? String == "Farmer Carry")
        #expect(adhocJSON["standaloneWorkoutSetId"] == nil)
    }
}
