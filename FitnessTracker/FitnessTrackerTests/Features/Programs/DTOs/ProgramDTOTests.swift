import Foundation
import Testing
@testable import FitnessTracker

@Suite("Program DTOs")
struct ProgramDTOTests {
    private let decoder = JSONCoding.decoder

    // MARK: - ProgramSummaryDTO

    @Test("ProgramSummaryDTO decodes server response with _count.weeks")
    func summaryDecodesCount() throws {
        let json = #"""
        {
          "id": "p1",
          "name": "Strength Base",
          "description": "A 12-week strength program.",
          "createdAt": "2026-01-15T12:00:00Z",
          "_count": { "weeks": 12 }
        }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(ProgramSummaryDTO.self, from: json)

        #expect(dto.id == "p1")
        #expect(dto.name == "Strength Base")
        #expect(dto.description == "A 12-week strength program.")
        #expect(dto.count.weeks == 12)
    }

    @Test("ProgramSummaryDTO accepts null description")
    func summaryDecodesNullDescription() throws {
        let json = #"""
        { "id": "p1", "name": "X", "description": null, "createdAt": "2026-01-15T12:00:00Z", "_count": { "weeks": 4 } }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(ProgramSummaryDTO.self, from: json)
        #expect(dto.description == nil)
    }

    // MARK: - ProgramDayDTO

    @Test("ProgramDayDTO decodes nested exercise tree with enum and optionals")
    func dayDecodesNestedTree() throws {
        let json = #"""
        {
          "id": "d1",
          "programWeekId": "w1",
          "dayNumber": 1,
          "name": "Push Day",
          "warmUp": null,
          "exerciseGroups": [
            {
              "id": "g1",
              "programDayId": "d1",
              "order": 0,
              "type": "STANDARD",
              "restSeconds": 90,
              "exercises": [
                {
                  "id": "pe1",
                  "exerciseGroupId": "g1",
                  "exerciseId": "ex1",
                  "order": 0,
                  "exercise": { "id": "ex1", "name": "Bench Press" },
                  "sets": [
                    { "id": "s1", "programExerciseId": "pe1", "setNumber": 1, "reps": 5, "weight": 135.5, "rpe": null, "notes": null, "effortTarget": null }
                  ]
                }
              ]
            }
          ]
        }
        """#.data(using: .utf8)!

        let day = try decoder.decode(ProgramDayDTO.self, from: json)

        #expect(day.id == "d1")
        #expect(day.name == "Push Day")
        #expect(day.warmUp == nil)
        #expect(day.exerciseGroups.count == 1)

        let group = day.exerciseGroups[0]
        #expect(group.type == .standard)
        #expect(group.restSeconds == 90)

        let pe = group.exercises[0]
        #expect(pe.exercise.name == "Bench Press")
        // Ref-style nested exercise (no description field) should decode with description == nil
        #expect(pe.exercise.description == nil)

        let set = pe.sets[0]
        #expect(set.reps == 5)
        #expect(set.weight == 135.5)
        #expect(set.rpe == nil)
    }

    @Test("ExerciseGroupType decodes both raw values")
    func groupTypeDecodesAll() throws {
        let standard = try decoder.decode(ExerciseGroupType.self, from: #""STANDARD""#.data(using: .utf8)!)
        let superset = try decoder.decode(ExerciseGroupType.self, from: #""SUPERSET""#.data(using: .utf8)!)
        #expect(standard == .standard)
        #expect(superset == .superset)
    }
}
