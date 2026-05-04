import Foundation

nonisolated struct ProgramDetailDTO: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let description: String?
    let createdAt: Date
    let weeks: [ProgramWeekDTO]
}

nonisolated struct ProgramWeekDTO: Codable, Sendable, Equatable {
    let id: String
    let programId: String
    let weekNumber: Int
    let days: [String]
}
