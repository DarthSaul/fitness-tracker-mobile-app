import Foundation
import Testing
@testable import FitnessTracker

@Suite("ProgramProgress")
struct ProgramProgressTests {
    private func session(week: Int, day: Int, status: String) throws -> ActiveProgramSessionDTO {
        try SocialFixtures.decode(ActiveProgramSessionDTO.self, """
        {"id":"s-\(week)-\(day)-\(status)","userId":"u","userProgramId":"up","weekNumber":\(week),"dayNumber":\(day),
         "status":"\(status)","startedAt":"2026-10-01T10:00:00.000Z","completedAt":null,"notes":null,
         "_count":{"completedSets":0}}
        """)
    }

    @Test("no program means no progress")
    func noProgram() {
        let progress = ProgramProgress(program: nil, sessions: [])
        #expect(progress.totalDays == 0)
        #expect(progress.completedDays == 0)
        #expect(progress.percent == 0)
    }

    @Test("counts distinct completed days, ignoring in-progress sessions")
    func distinctDays() throws {
        let sessions = [
            try session(week: 1, day: 1, status: "COMPLETED"),
            try session(week: 1, day: 1, status: "COMPLETED"),
            try session(week: 1, day: 2, status: "COMPLETED"),
            try session(week: 1, day: 3, status: "IN_PROGRESS"),
        ]
        #expect(ProgramProgress(program: nil, sessions: sessions).completedDays == 2)
    }
}

@Suite("TabSelection Program section")
@MainActor
struct ProgramTabSelectionTests {
    @Test("opens on Manage, and Explore can be selected from elsewhere")
    func programSection() {
        let selection = TabSelection()
        #expect(selection.programSection == .manage)
        selection.selectProgram(.explore)
        #expect(selection.current == .programs)
        #expect(selection.programSection == .explore)
    }

    @Test("sections are Manage then Explore")
    func order() {
        #expect(ProgramSection.allCases.map(\.title) == ["Manage", "Explore"])
    }
}
