import Foundation

/// The compact relative times the Friends screens use: "now", "5m", "2h",
/// "Yesterday", "3d", then a short date ("Sep 22", or "Sep 22, 2025" in
/// another year).
nonisolated enum RelativeTime {
    static func short(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0
        if days <= 1 { return "Yesterday" }
        if days < 7 { return "\(days)d" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return sameYear ? date.formatted(style) : date.formatted(style.year())
    }
}
