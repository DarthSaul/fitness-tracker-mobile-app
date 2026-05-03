import Foundation

nonisolated struct UserProgramDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let userId: String
    let programId: String
    let isActive: Bool
    let currentWeek: Int
    let currentDay: Int
    let startedAt: Date
}

/// POST /api/user-programs returns the saved record with a nested program summary.
nonisolated struct UserProgramWithProgramDTO: Codable, Sendable, Equatable {
    let id: String
    let userId: String
    let programId: String
    let isActive: Bool
    let currentWeek: Int
    let currentDay: Int
    let startedAt: Date
    let program: NestedProgram

    nonisolated struct NestedProgram: Codable, Sendable, Equatable {
        let id: String
        let name: String
        let description: String?
    }
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
