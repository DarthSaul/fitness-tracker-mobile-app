import Foundation

/// A calendar day with no time of day or time zone: the wire form of a
/// Postgres `DATE` column (e.g. `ScheduledWorkout.scheduledDate`).
///
/// The server sends these as UTC midnight (`"2026-10-08T00:00:00.000Z"`), and
/// treating that as a moment in time puts the day on the previous evening west
/// of UTC. So it decodes from the UTC components and encodes as `"yyyy-MM-dd"`,
/// which the server stores as that same day in every time zone. Compare it to a
/// local date with `CalendarDay(date, in: calendar)`, never as a `Date`.
nonisolated struct CalendarDay: Hashable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone.
    init(_ date: Date, in calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    /// `"yyyy-MM-dd"`: the wire format and the calendar views' day key.
    var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: - Codable

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let day = Self.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a yyyy-MM-dd day or an ISO 8601 UTC-midnight timestamp, got '\(raw)'"
            )
        }
        self = day
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }

    /// Accepts a bare `"yyyy-MM-dd"` or a full ISO 8601 timestamp, whose day
    /// is read in UTC (the server's encoding of a `DATE`).
    static func parse(_ raw: String) -> CalendarDay? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        if raw.count == 10, parts.count == 3,
           let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
            return CalendarDay(year: year, month: month, day: day)
        }
        guard let date = JSONCoding.parseISO8601(raw) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        return CalendarDay(date, in: utc)
    }
}
