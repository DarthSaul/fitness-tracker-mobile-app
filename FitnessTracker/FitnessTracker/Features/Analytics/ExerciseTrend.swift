import Foundation

/// The range picker under the e1RM chart.
nonisolated enum TrendRange: String, CaseIterable, Identifiable, Sendable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "All"

    var id: String { rawValue }

    /// Days back from now; nil for all time.
    var days: Int? {
        switch self {
        case .oneMonth: 30
        case .threeMonths: 90
        case .sixMonths: 180
        case .oneYear: 365
        case .all: nil
        }
    }
}

/// Everything the exercise detail shows, derived on the device from
/// `GET /api/analytics/exercises/:id` (which returns the exercise's full
/// history, every set included) — so changing the range never refetches.
nonisolated struct ExerciseTrend: Sendable {
    struct Point: Identifiable, Equatable, Sendable {
        let id: String
        let date: Date
        let e1rm: Double
    }

    struct TopSet: Equatable, Sendable {
        let weight: Double
        let reps: Int
        let e1rm: Double
        let date: Date
    }

    struct RecentSession: Identifiable, Equatable, Sendable {
        let id: String
        let date: Date
        let setCount: Int
        let topSet: TopSet?
        let e1rm: Double?
    }

    /// Sessions with an e1RM inside the range, oldest first.
    let points: [Point]
    /// The most recent e1RM overall — the headline number, whatever the range.
    let current: Point?
    /// Change across the range (last − first point); nil with fewer than two.
    let change: Double?
    /// When the range's first point was, for "since Jul".
    let changeSince: Date?
    /// The all-time best set by e1RM.
    let bestSet: TopSet?
    /// Every session, newest first.
    let recentSessions: [RecentSession]

    init(history: [AnalyticsExerciseHistoryDTO.SessionEntry], range: TrendRange, now: Date = .now) {
        let chronological = history.sorted { $0.completedAt < $1.completedAt }
        let allPoints = chronological.compactMap { entry in
            entry.bestE1rm.map { Point(id: entry.sessionId, date: entry.completedAt, e1rm: $0) }
        }
        let cutoff = range.days.map { now.addingTimeInterval(-Double($0) * 86_400) }
        let points = cutoff.map { cutoff in allPoints.filter { $0.date >= cutoff } } ?? allPoints

        self.points = points
        current = allPoints.last
        if points.count >= 2, let first = points.first, let last = points.last {
            change = last.e1rm - first.e1rm
            changeSince = first.date
        } else {
            change = nil
            changeSince = nil
        }

        bestSet = chronological
            .flatMap { entry in entry.sets.compactMap { Self.topSet($0, date: entry.completedAt) } }
            .max { $0.e1rm < $1.e1rm }

        recentSessions = chronological.reversed().map { entry in
            RecentSession(
                id: entry.sessionId,
                date: entry.completedAt,
                setCount: entry.sets.count,
                topSet: entry.sets.compactMap { Self.topSet($0, date: entry.completedAt) }.max { $0.e1rm < $1.e1rm },
                e1rm: entry.bestE1rm
            )
        }
    }

    private static func topSet(_ set: AnalyticsExerciseHistoryDTO.SessionSet, date: Date) -> TopSet? {
        guard let weight = set.weight, let reps = set.reps, let e1rm = set.e1rm else { return nil }
        return TopSet(weight: weight, reps: reps, e1rm: e1rm, date: date)
    }

    // MARK: - Chart scale

    /// Three evenly spaced, round gridline values that bracket `values`
    /// (e.g. 380 / 420 / 460), for the chart's labeled gridlines.
    static func gridlines(for values: [Double]) -> [Double] {
        guard let low = values.min(), let high = values.max() else { return [0, 50, 100] }
        let span = max(high - low, 10)
        var step = niceStep(span / 2)
        var start = (low / step).rounded(.down) * step
        // Widen until three lines reach the top value.
        while start + 2 * step < high {
            step = niceStep(step * 1.5)
            start = (low / step).rounded(.down) * step
        }
        return [start, start + step, start + 2 * step]
    }

    /// The next "round" step at or above `raw`: 1, 2, 2.5 or 5 × 10ⁿ.
    static func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let magnitude = pow(10, (log10(raw)).rounded(.down))
        for multiplier in [1, 2, 2.5, 5, 10] where multiplier * magnitude >= raw {
            return multiplier * magnitude
        }
        return 10 * magnitude
    }

    // MARK: - Formatting

    /// "+74", "−5", or nil when there's no change to show.
    static func formatChange(_ change: Double) -> String {
        let rounded = Int(change.rounded())
        if rounded > 0 { return "+\(rounded)" }
        if rounded < 0 { return "−\(abs(rounded))" }
        return "±0"
    }

    /// "405 × 3".
    static func formatSet(_ set: TopSet) -> String {
        "\(formatWeight(set.weight)) × \(set.reps)"
    }

    static func formatWeight(_ weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
    }
}
