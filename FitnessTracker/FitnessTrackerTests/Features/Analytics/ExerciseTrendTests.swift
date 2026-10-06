import Foundation
import Testing
@testable import FitnessTracker

@Suite("ExerciseTrend")
struct ExerciseTrendTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func entry(
        _ id: String,
        daysAgo: Double,
        sets: [(weight: Double, reps: Int, e1rm: Double)]
    ) -> AnalyticsExerciseHistoryDTO.SessionEntry {
        AnalyticsExerciseHistoryDTO.SessionEntry(
            sessionId: id,
            completedAt: now.addingTimeInterval(-daysAgo * 86_400),
            type: "PROGRAM",
            weekNumber: 1,
            dayNumber: 1,
            workoutLabel: nil,
            sets: sets.map { .init(reps: $0.reps, weight: $0.weight, e1rm: $0.e1rm) },
            bestE1rm: sets.map(\.e1rm).max(),
            totalVolume: nil
        )
    }

    private var history: [AnalyticsExerciseHistoryDTO.SessionEntry] {
        [
            entry("old", daysAgo: 200, sets: [(300, 5, 350)]),
            entry("a", daysAgo: 80, sets: [(330, 5, 385), (340, 3, 374)]),
            entry("b", daysAgo: 40, sets: [(360, 3, 396)]),
            entry("c", daysAgo: 5, sets: [(405, 3, 446), (385, 5, 449)]),
        ]
    }

    @Test("the range filters points; the headline is always the latest e1RM")
    func rangeFiltering() {
        let threeMonths = ExerciseTrend(history: history, range: .threeMonths, now: now)
        #expect(threeMonths.points.map(\.id) == ["a", "b", "c"])
        #expect(threeMonths.current?.e1rm == 449)

        let oneMonth = ExerciseTrend(history: history, range: .oneMonth, now: now)
        #expect(oneMonth.points.map(\.id) == ["c"])
        #expect(oneMonth.current?.e1rm == 449)

        #expect(ExerciseTrend(history: history, range: .all, now: now).points.count == 4)
    }

    @Test("change is last minus first in range, and needs two points")
    func change() {
        let trend = ExerciseTrend(history: history, range: .threeMonths, now: now)
        #expect(trend.change == 449 - 385)
        #expect(trend.changeSince == now.addingTimeInterval(-80 * 86_400))

        #expect(ExerciseTrend(history: history, range: .oneMonth, now: now).change == nil)
    }

    @Test("best set is the all-time set with the highest e1RM")
    func bestSet() {
        let best = ExerciseTrend(history: history, range: .oneMonth, now: now).bestSet
        #expect(best?.weight == 385)
        #expect(best?.reps == 5)
        #expect(best.map(ExerciseTrend.formatSet) == "385 × 5")
    }

    @Test("recent sessions are newest first with their top set")
    func recentSessions() {
        let sessions = ExerciseTrend(history: history, range: .threeMonths, now: now).recentSessions
        #expect(sessions.map(\.id) == ["c", "b", "a", "old"])
        #expect(sessions[0].setCount == 2)
        #expect(sessions[0].topSet?.weight == 385)
    }

    @Test("gridlines are three round values bracketing the data")
    func gridlines() {
        let lines = ExerciseTrend.gridlines(for: [372, 446])
        #expect(lines.count == 3)
        #expect(lines[0] <= 372)
        #expect(lines[2] >= 446)
        #expect(lines[1] - lines[0] == lines[2] - lines[1])
        #expect(lines.allSatisfy { $0.truncatingRemainder(dividingBy: 5) == 0 })

        let flat = ExerciseTrend.gridlines(for: [200])
        #expect(flat[0] <= 200 && flat[2] >= 200)
    }

    @Test("change is formatted with a sign")
    func formatting() {
        #expect(ExerciseTrend.formatChange(74.4) == "+74")
        #expect(ExerciseTrend.formatChange(-5) == "−5")
        #expect(ExerciseTrend.formatChange(0.2) == "±0")
        #expect(ExerciseTrend.formatWeight(102.5) == "102.5")
    }
}

@Suite("WorkoutCalendar")
struct WorkoutCalendarTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ iso: String) -> Date {
        JSONCoding.parseISO8601(iso)!
    }

    @Test("counts workouts per month by local day")
    func monthCounts() {
        let workoutCalendar = WorkoutCalendar(completionDates: [
            date("2026-09-03T10:00:00Z"),
            date("2026-09-22T10:00:00Z"),
            date("2026-09-22T18:00:00Z"),
            date("2026-10-01T08:00:00Z"),
        ], calendar: calendar)
        #expect(workoutCalendar.workoutCount(inMonthOf: date("2026-09-15T00:00:00Z")) == 3)
        #expect(workoutCalendar.hasWorkout(on: date("2026-09-22T23:00:00Z")))
        #expect(!workoutCalendar.hasWorkout(on: date("2026-09-21T12:00:00Z")))
    }

    @Test("the grid starts on the locale's first weekday")
    func grid() {
        // September 2026 starts on a Tuesday: two blanks before the 1st.
        let grid = WorkoutCalendar(completionDates: [], calendar: calendar).gridDays(forMonthOf: date("2026-09-10T00:00:00Z"))
        #expect(grid.prefix(2).allSatisfy { $0 == nil })
        #expect(grid[2] == date("2026-09-01T00:00:00Z"))
        #expect(grid.compactMap { $0 }.count == 30)

        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let mondayGrid = WorkoutCalendar(completionDates: [], calendar: mondayFirst).gridDays(forMonthOf: date("2026-09-10T00:00:00Z"))
        #expect(mondayGrid.prefix(1).allSatisfy { $0 == nil })
        #expect(mondayGrid[1] == date("2026-09-01T00:00:00Z"))
    }

    @Test("weekday letters follow the first weekday")
    func weekdaySymbols() {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        mondayFirst.locale = Locale(identifier: "en_US")
        #expect(WorkoutCalendar(completionDates: [], calendar: mondayFirst).weekdaySymbols == ["M", "T", "W", "T", "F", "S", "S"])
    }
}

@Suite("Weekly volume")
@MainActor
struct WeeklyVolumeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ iso: String) -> Date {
        JSONCoding.parseISO8601(iso)!
    }

    @Test("nine local weeks ending with the current one, counting completions in each")
    func buckets() {
        // Wednesday 2026-09-30; Sunday-first weeks.
        let now = date("2026-09-30T12:00:00Z")
        let weeks = WeeklyVolumeCard.weeks(from: [
            date("2026-07-01T10:00:00Z"), // outside the window
            date("2026-09-20T09:00:00Z"), // Sun — first day of last week
            date("2026-09-26T23:00:00Z"), // Sat — last day of last week
            date("2026-09-27T08:00:00Z"), // Sun — this week
        ], now: now, calendar: calendar)

        #expect(weeks.count == 9)
        #expect(weeks.last?.start == date("2026-09-27T00:00:00Z"))
        #expect(weeks.first?.start == date("2026-08-02T00:00:00Z"))
        #expect(weeks.map(\.sessions) == [0, 0, 0, 0, 0, 0, 0, 2, 1])
    }

    @Test("no completions yields nine empty weeks")
    func empty() {
        let weeks = WeeklyVolumeCard.weeks(from: [], now: date("2026-09-30T12:00:00Z"), calendar: calendar)
        #expect(weeks.count == 9)
        #expect(weeks.allSatisfy { $0.sessions == 0 })
    }
}
