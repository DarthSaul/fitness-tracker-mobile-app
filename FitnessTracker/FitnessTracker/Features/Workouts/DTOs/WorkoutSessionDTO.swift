import Foundation

nonisolated struct WorkoutSessionDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let userId: String
    let userProgramId: String
    let weekNumber: Int
    let dayNumber: Int
    let status: SessionStatus
    let startedAt: Date
    let completedAt: Date?
    let notes: String?
}
