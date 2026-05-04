import Foundation

nonisolated struct AnalyticsDashboardDTO: Codable, Sendable, Equatable {
    let totalSessions: Int
    let totalVolumeLbs: Double
    let currentStreakDays: Int
    let longestStreakDays: Int
    let lastWorkoutAt: Date?
    let totalExercises: Int
    let sessionsThisWeek: Int
}
