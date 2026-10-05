import Foundation

/// Progress through the active program run, shared by Home's Next Up card
/// and the Program tab's progress ring so both count the same way.
nonisolated struct ProgramProgress: Equatable, Sendable {
    let completedDays: Int
    let totalDays: Int

    init(program: ActiveUserProgramDTO?, sessions: [ActiveProgramSessionDTO]) {
        totalDays = program?.program.weeks.reduce(0) { $0 + $1.days.count } ?? 0
        // Distinct days, not sessions: a day logged twice must not push
        // progress past 100%.
        completedDays = Set(
            sessions
                .filter { $0.status == .completed }
                .map { "\($0.weekNumber)-\($0.dayNumber)" }
        ).count
    }

    /// Integer percentage clamped to 0...100; 0 when the program has no days.
    var percent: Int {
        guard totalDays > 0 else { return 0 }
        return min(100, max(0, Int((Double(completedDays) / Double(totalDays) * 100).rounded())))
    }
}
