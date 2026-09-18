import Foundation
import Testing
@testable import FitnessTracker

@Suite("UserProgram DTOs")
struct UserProgramDTOTests {
    @Test("list row decodes the run fields")
    func decodesRunFields() throws {
        let json = """
        [{
          "id": "up2", "userId": "u1", "programId": "p1",
          "isActive": false, "currentWeek": 4, "currentDay": 5,
          "startedAt": "2026-06-01T00:00:00Z",
          "completedAt": "2026-07-04T18:22:11Z",
          "archivedAt": null,
          "runNumber": 2,
          "completedRunCount": 2,
          "program": { "id": "p1", "name": "Arm Farm", "description": null }
        }]
        """.data(using: .utf8)!

        let rows = try JSONCoding.decoder.decode([UserProgramWithProgramDTO].self, from: json)

        let row = try #require(rows.first)
        #expect(row.completedAt != nil)
        #expect(row.archivedAt == nil)
        #expect(row.runNumber == 2)
        #expect(row.completedRunCount == 2)
        #expect(row.isCompleted == true)
        #expect(row.isActiveRun == false)
    }

    @Test("activate / save response decodes without the list-only run fields")
    func decodesWithoutListOnlyFields() throws {
        let json = """
        {
          "id": "up3", "userId": "u1", "programId": "p1",
          "isActive": true, "currentWeek": 1, "currentDay": 1,
          "startedAt": "2026-09-18T12:00:00Z",
          "completedAt": null, "archivedAt": null,
          "program": { "id": "p1", "name": "Arm Farm", "description": null }
        }
        """.data(using: .utf8)!

        let row = try JSONCoding.decoder.decode(UserProgramWithProgramDTO.self, from: json)

        #expect(row.runNumber == nil)
        #expect(row.completedRunCount == nil)
        #expect(row.isCompleted == false)
        #expect(row.isActiveRun == true)
    }

    @Test("rows from a pre-runs server (no run keys at all) still decode")
    func decodesLegacyShape() throws {
        let json = """
        {
          "id": "up1", "userId": "u1", "programId": "p1",
          "isActive": true, "currentWeek": 1, "currentDay": 1,
          "startedAt": "2026-09-18T12:00:00Z"
        }
        """.data(using: .utf8)!

        let row = try JSONCoding.decoder.decode(UserProgramDTO.self, from: json)

        #expect(row.completedAt == nil)
        #expect(row.archivedAt == nil)
    }

    @Test("a row that is isActive but completed is not an active run")
    func completedButActiveRowIsNotActiveRun() throws {
        let json = """
        {
          "id": "up1", "userId": "u1", "programId": "p1",
          "isActive": true, "currentWeek": 4, "currentDay": 5,
          "startedAt": "2026-06-01T00:00:00Z",
          "completedAt": "2026-07-04T18:22:11Z", "archivedAt": null,
          "program": { "id": "p1", "name": "Arm Farm", "description": null }
        }
        """.data(using: .utf8)!

        let row = try JSONCoding.decoder.decode(UserProgramWithProgramDTO.self, from: json)

        #expect(row.isActiveRun == false)
    }
}
