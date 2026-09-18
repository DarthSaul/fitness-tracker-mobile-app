import Foundation

// Each UserProgram row is one RUN through a program, so a user may hold many
// rows per program. A run is "open" until it is completed (`completedAt`) or
// unsaved-with-history (`archivedAt`); both are terminal. Activating a
// terminal run never resumes it — the server activates the program's open
// run, creating a fresh one at week 1 day 1 when needed, so the activate
// response may carry a different id than the one requested.
//
// The run fields are `var … = nil` (not `let`) so they still decode while
// staying optional in the memberwise init.

nonisolated struct UserProgramDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let userId: String
    let programId: String
    let isActive: Bool
    let currentWeek: Int
    let currentDay: Int
    let startedAt: Date
    var completedAt: Date? = nil
    var archivedAt: Date? = nil
}

/// A run with a nested program summary. Returned by GET /api/user-programs
/// (one current run per program: the open run, else the latest completed one)
/// and by the save / activate mutations.
nonisolated struct UserProgramWithProgramDTO: Codable, Sendable, Equatable {
    let id: String
    let userId: String
    let programId: String
    let isActive: Bool
    let currentWeek: Int
    let currentDay: Int
    let startedAt: Date
    let program: NestedProgram
    var completedAt: Date? = nil
    var archivedAt: Date? = nil
    /// 1-based position of this run among the user's runs of the program.
    /// List-only — absent on the save / activate responses.
    var runNumber: Int? = nil
    /// Completed runs of this program, including archived ones. List-only.
    var completedRunCount: Int? = nil

    nonisolated struct NestedProgram: Codable, Sendable, Equatable {
        let id: String
        let name: String
        let description: String?
    }

    var isCompleted: Bool { completedAt != nil }

    /// Until the server's reconcile migration lands, old rows can still be
    /// `isActive` while completed — so "active" must also mean not finished.
    var isActiveRun: Bool { isActive && completedAt == nil }
}

/// GET /api/user-programs/active includes the full program tree.
nonisolated struct ActiveUserProgramDTO: Codable, Sendable, Equatable {
    let id: String
    let userId: String
    let programId: String
    let isActive: Bool
    let currentWeek: Int
    let currentDay: Int
    let startedAt: Date
    let program: ActiveProgramDetail
    var completedAt: Date? = nil
    var archivedAt: Date? = nil

    nonisolated struct ActiveProgramDetail: Codable, Sendable, Equatable {
        let id: String
        let name: String
        let description: String?
        let createdAt: Date
        let weeks: [ActiveProgramWeek]
    }

    nonisolated struct ActiveProgramWeek: Codable, Sendable, Equatable {
        let id: String
        let programId: String
        let weekNumber: Int
        let days: [ProgramDayDTO]
    }
}
