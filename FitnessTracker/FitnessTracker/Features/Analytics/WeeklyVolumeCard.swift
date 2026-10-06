import Charts
import SwiftUI

/// "Weekly volume": completed workouts per week over the last 9 weeks,
/// bucketed into local weeks on the device from `GET /api/history/dates`
/// (see `weeks(from:)`). `weeks == nil` renders the loading placeholder.
struct WeeklyVolumeCard: View {
    struct Week: Identifiable {
        let start: Date
        let sessions: Int
        var id: Date { start }
    }

    static let weekCount = 9

    let weeks: [Week]?
    var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly volume")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("Last \(Self.weekCount) weeks")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if let weeks {
                chart(weeks)
            } else if let errorMessage {
                Text("Couldn't load weekly volume: \(errorMessage)")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 130)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func chart(_ weeks: [Week]) -> some View {
        let maxSessions = Self.maxSessions(weeks)
        return Chart {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    BarMark(
                        x: .value("Week", index),
                        // The current, unfinished week keeps a 3% stub so it
                        // still reads as a bar.
                        y: .value("Workouts", max(Double(week.sessions), maxSessions * 0.03)),
                        width: .ratio(0.78)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(barColor(index: index, count: weeks.count))
                }
            }
            .chartXAxis {
                AxisMarks(values: Array(weeks.indices)) { value in
                    if let index = value.as(Int.self), index % 2 == 0 {
                        AxisValueLabel(centered: true) {
                            Text(weeks[index].start, format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 10))
                                .foregroundStyle(SocialStyle.tertiaryText)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...maxSessions)
            .frame(height: 130)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilitySummary(weeks))
    }

    private static func maxSessions(_ weeks: [Week]) -> Double {
        Double(max(weeks.map(\.sessions).max() ?? 1, 1))
    }

    /// Past weeks translucent blue, the last completed week solid blue, the
    /// current week gray.
    private func barColor(index: Int, count: Int) -> Color {
        if index == count - 1 { return Color(.systemGray4) }
        if index == count - 2 { return .blue }
        return Color.blue.opacity(0.45)
    }

    private static func accessibilitySummary(_ weeks: [Week]) -> String {
        let counts = weeks.map { "\($0.sessions)" }.joined(separator: ", ")
        return "Workouts per week, oldest to newest: \(counts)"
    }

    /// `weekCount` local weeks ending with the current one (weeks start on
    /// the locale's first weekday), each counting the completions inside it.
    /// Completions outside the window are ignored.
    static func weeks(
        from completionDates: [Date],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Week] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let starts = (0..<weekCount).compactMap {
            calendar.date(byAdding: .weekOfYear, value: $0 - (weekCount - 1), to: thisWeek)
        }
        var counts: [Date: Int] = [:]
        for date in completionDates {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            counts[start, default: 0] += 1
        }
        return starts.map { Week(start: $0, sessions: counts[$0] ?? 0) }
    }
}
