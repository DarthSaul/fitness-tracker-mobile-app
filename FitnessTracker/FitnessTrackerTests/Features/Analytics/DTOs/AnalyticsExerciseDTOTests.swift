import Foundation
import Testing
@testable import FitnessTracker

@Suite("Analytics exercise DTOs")
struct AnalyticsExerciseDTOTests {
    private let decoder = JSONCoding.decoder

    @Test("trend history decodes program and standalone entries side by side")
    func mixedTrendHistoryDecodes() throws {
        let json = #"""
        {
          "exercise": { "id": "e1", "name": "Goblet Squat" },
          "history": [
            {
              "sessionId": "s1",
              "completedAt": "2026-08-10T18:00:00Z",
              "type": "PROGRAM",
              "weekNumber": 2,
              "dayNumber": 3,
              "workoutLabel": null,
              "sets": [{ "reps": 5, "weight": 135.0, "e1rm": 157.5 }],
              "bestE1rm": 157.5,
              "totalVolume": 675
            },
            {
              "sessionId": "s2",
              "completedAt": "2026-08-12T18:00:00Z",
              "type": "STANDALONE",
              "weekNumber": null,
              "dayNumber": null,
              "workoutLabel": "KB Only #1",
              "sets": [{ "reps": 8, "weight": 53.0, "e1rm": 67.1 }],
              "bestE1rm": 67.1,
              "totalVolume": 424
            }
          ]
        }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(AnalyticsExerciseHistoryDTO.self, from: json)

        #expect(dto.history.count == 2)

        let program = dto.history[0]
        #expect(program.type == AnalyticsExerciseHistoryDTO.SessionEntry.programType)
        #expect(program.weekNumber == 2)
        #expect(program.dayNumber == 3)
        #expect(program.workoutLabel == nil)
        #expect(program.contextLabel == "W2 · D3")

        let standalone = dto.history[1]
        #expect(standalone.type == AnalyticsExerciseHistoryDTO.SessionEntry.standaloneType)
        #expect(standalone.weekNumber == nil)
        #expect(standalone.dayNumber == nil)
        #expect(standalone.workoutLabel == "KB Only #1")
        #expect(standalone.contextLabel == "KB Only #1")
        #expect(standalone.bestE1rm == 67.1)
    }

    @Test("trend history decodes legacy entries without type or workoutLabel")
    func legacyTrendEntryDecodes() throws {
        // Servers that predate the standalone rollout omit both new keys —
        // the optional fields must decode as nil, not fail the payload.
        let json = #"""
        {
          "exercise": { "id": "e1", "name": "Back Squat" },
          "history": [
            {
              "sessionId": "s1",
              "completedAt": "2026-05-03T18:00:00Z",
              "weekNumber": 1,
              "dayNumber": 1,
              "sets": [],
              "bestE1rm": null,
              "totalVolume": null
            }
          ]
        }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(AnalyticsExerciseHistoryDTO.self, from: json)

        #expect(dto.history.count == 1)
        #expect(dto.history[0].type == nil)
        #expect(dto.history[0].workoutLabel == nil)
        #expect(dto.history[0].weekNumber == 1)
        #expect(dto.history[0].dayNumber == 1)
        #expect(dto.history[0].contextLabel == "W1 · D1")
    }

    @Test("an unrecognized future type value decodes rather than failing the payload")
    func unknownTypeDecodes() throws {
        let json = #"""
        {
          "exercise": { "id": "e1", "name": "Plank" },
          "history": [
            {
              "sessionId": "s1",
              "completedAt": "2026-08-12T18:00:00Z",
              "type": "CORE",
              "weekNumber": null,
              "dayNumber": null,
              "workoutLabel": "Core circuit",
              "sets": [],
              "bestE1rm": null,
              "totalVolume": null
            }
          ]
        }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(AnalyticsExerciseHistoryDTO.self, from: json)

        #expect(dto.history[0].type == "CORE")
        #expect(dto.history[0].workoutLabel == "Core circuit")
        #expect(dto.history[0].contextLabel == "Core circuit")
    }

    @Test("standalone entry without a workout label falls back to Standalone")
    func standaloneEntryWithoutLabelFallsBack() throws {
        let json = #"""
        {
          "exercise": { "id": "e1", "name": "Goblet Squat" },
          "history": [
            {
              "sessionId": "s1",
              "completedAt": "2026-08-12T18:00:00Z",
              "type": "STANDALONE",
              "weekNumber": null,
              "dayNumber": null,
              "workoutLabel": null,
              "sets": [],
              "bestE1rm": null,
              "totalVolume": null
            }
          ]
        }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(AnalyticsExerciseHistoryDTO.self, from: json)

        #expect(dto.history[0].contextLabel == "Standalone")
    }
}
