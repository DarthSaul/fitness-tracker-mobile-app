import Foundation

/// The first day of the user's week (`weekStartDay` on `GET /api/auth/me`).
/// The server uses it for "this week" in the weekly goal and the analytics
/// dashboard; the client buckets the weekly volume chart with it so all
/// three agree. An unrecognized value decodes as `.sunday`, the default.
nonisolated enum WeekStartDay: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case sunday = "SUNDAY"
    case monday = "MONDAY"
    case tuesday = "TUESDAY"
    case wednesday = "WEDNESDAY"
    case thursday = "THURSDAY"
    case friday = "FRIDAY"
    case saturday = "SATURDAY"

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WeekStartDay(rawValue: raw) ?? .sunday
    }

    var id: Self { self }

    /// `Calendar.firstWeekday` numbering: 1 is Sunday, 7 is Saturday.
    var calendarWeekday: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }

    /// "Monday", in the user's locale.
    var displayName: String {
        Calendar.current.standaloneWeekdaySymbols[calendarWeekday - 1]
    }

    /// `base` with its weeks starting on this day.
    func calendar(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = calendarWeekday
        return calendar
    }
}
