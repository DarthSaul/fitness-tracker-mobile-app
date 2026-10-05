import Foundation

/// Month math for the History calendar: which local days have a completed
/// workout (from `GET /api/history/dates` instants), the month grid, and the
/// month's summary.
nonisolated struct WorkoutCalendar: Sendable {
    let calendar: Calendar
    /// Start-of-day for every day with at least one completed workout,
    /// with how many workouts finished that day.
    let workoutsByDay: [Date: Int]

    init(completionDates: [Date], calendar: Calendar = .current) {
        self.calendar = calendar
        var counts: [Date: Int] = [:]
        for date in completionDates {
            counts[calendar.startOfDay(for: date), default: 0] += 1
        }
        workoutsByDay = counts
    }

    func hasWorkout(on day: Date) -> Bool {
        workoutsByDay[calendar.startOfDay(for: day)] != nil
    }

    func monthStart(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Workouts completed in the month containing `month`.
    func workoutCount(inMonthOf month: Date) -> Int {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
        return workoutsByDay.reduce(0) { total, entry in
            interval.contains(entry.key) ? total + entry.value : total
        }
    }

    /// The latest day with a workout in that month, if any.
    func mostRecentWorkoutDay(inMonthOf month: Date) -> Date? {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return nil }
        return workoutsByDay.keys.filter { interval.contains($0) }.max()
    }

    /// The month as grid cells, week rows from the locale's first weekday:
    /// nil for the blanks before the 1st, then each day.
    func gridDays(forMonthOf month: Date) -> [Date?] {
        let start = monthStart(for: month)
        guard let days = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let dates = days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
        return Array(repeating: nil, count: leading) + dates.map { Optional($0) }
    }

    /// One-letter weekday headers in grid order ("S M T W T F S").
    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}
