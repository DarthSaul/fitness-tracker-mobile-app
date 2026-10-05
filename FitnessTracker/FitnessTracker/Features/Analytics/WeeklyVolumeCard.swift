import Charts
import SwiftUI

/// "Weekly volume": completed workouts per week over the last 9 weeks.
///
/// Placeholder data for now — the bars are static sample values until the
/// real counts are wired (they can come from `GET /api/history/dates`,
/// bucketed into local weeks on the device).
struct WeeklyVolumeCard: View {
    struct Week: Identifiable {
        let start: Date
        let sessions: Int
        var id: Date { start }
    }

    var weeks: [Week] = WeeklyVolumeCard.sampleWeeks()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly volume")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("Last \(weeks.count) weeks")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    BarMark(
                        x: .value("Week", index),
                        // The current, unfinished week keeps a 3% stub so it
                        // still reads as a bar.
                        y: .value("Workouts", max(Double(week.sessions), maxSessions * 0.03)),
                        width: .ratio(0.78)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(barColor(index: index))
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
            .accessibilityLabel(accessibilitySummary)

            Text("Sample data")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var maxSessions: Double {
        Double(max(weeks.map(\.sessions).max() ?? 1, 1))
    }

    /// Past weeks translucent blue, the last completed week solid blue, the
    /// current week gray.
    private func barColor(index: Int) -> Color {
        if index == weeks.count - 1 { return Color(.systemGray4) }
        if index == weeks.count - 2 { return .blue }
        return Color.blue.opacity(0.45)
    }

    private var accessibilitySummary: String {
        let counts = weeks.map { "\($0.sessions)" }.joined(separator: ", ")
        return "Workouts per week, oldest to newest: \(counts)"
    }

    /// Nine weeks ending with the current one, with static counts.
    static func sampleWeeks(now: Date = .now, calendar: Calendar = .current) -> [Week] {
        let counts = [3, 2, 4, 4, 3, 4, 2, 3, 1]
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return counts.enumerated().map { offset, sessions in
            let start = calendar.date(byAdding: .weekOfYear, value: offset - (counts.count - 1), to: thisWeek) ?? thisWeek
            return Week(start: start, sessions: sessions)
        }
    }
}
