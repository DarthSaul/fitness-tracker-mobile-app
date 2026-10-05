import Charts
import SwiftUI

/// The selected exercise's detail (design-spec Exercise detail): the e1RM
/// card with its chart and range picker, the best set, and recent sessions.
/// ("Friends' best" is left out: ADR 001 keeps other users' lifts private.)
struct ExerciseTrendDetail: View {
    let history: AnalyticsExerciseHistoryDTO
    @State private var range: TrendRange = .threeMonths

    private var trend: ExerciseTrend {
        ExerciseTrend(history: history.history, range: range)
    }

    var body: some View {
        let trend = trend
        VStack(alignment: .leading, spacing: 12) {
            if history.history.isEmpty {
                Text("No completed sessions found for this exercise")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                E1rmCard(trend: trend, range: $range)
                if let best = trend.bestSet {
                    BestSetCard(best: best)
                }
                RecentSessionsGroup(sessions: trend.recentSessions)
            }
        }
    }
}

// MARK: - e1RM card

private struct E1rmCard: View {
    let trend: ExerciseTrend
    @Binding var range: TrendRange
    /// The date under the user's finger, for tap-to-inspect.
    @State private var selectedDate: Date?

    private var selectedPoint: ExerciseTrend.Point? {
        guard let selectedDate, !trend.points.isEmpty else { return nil }
        return trend.points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selectedPoint.map { $0.date.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "Estimated 1RM")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let shown = selectedPoint ?? trend.current {
                    Text(ExerciseTrend.formatWeight(shown.e1rm.rounded()))
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                    Text("lbs")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selectedPoint == nil, let change = trend.change, let since = trend.changeSince {
                    Text("\(ExerciseTrend.formatChange(change)) since \(sinceLabel(since))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(change > 0 ? Color.green : Color.secondary)
                }
            }

            chart
                .padding(.top, 10)

            RangePicker(selection: $range)
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// "Jul", or "Sep 4" when the range is a month or less.
    private func sinceLabel(_ date: Date) -> String {
        range == .oneMonth
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated))
    }

    @ViewBuilder
    private var chart: some View {
        let points = trend.points
        if points.isEmpty {
            Text("No sessions in this range")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 150)
        } else {
            let gridlines = ExerciseTrend.gridlines(for: points.map(\.e1rm))
            let floor = gridlines.first ?? 0
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Floor", floor),
                        yEnd: .value("e1RM", point.e1rm)
                    )
                    .foregroundStyle(Color.green.opacity(0.12))
                    .interpolationMethod(.linear)

                    LineMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                }

                // The latest point (or the inspected one), ringed in the
                // card color.
                if let marked = selectedPoint ?? points.last {
                    PointMark(x: .value("Date", marked.date), y: .value("e1RM", marked.e1rm))
                        .symbol {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color(.secondarySystemBackground), lineWidth: 2))
                        }
                }
                if let selectedPoint {
                    RuleMark(x: .value("Date", selectedPoint.date))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartYScale(domain: floor...(gridlines.last ?? 100))
            .chartYAxis {
                AxisMarks(position: .trailing, values: gridlines) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color(.separator))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(ExerciseTrend.formatWeight(number))
                                .font(.system(size: 10))
                                .foregroundStyle(SocialStyle.tertiaryText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: range == .oneMonth
                        ? .dateTime.month(.abbreviated).day()
                        : .dateTime.month(.abbreviated))
                        .font(.system(size: 11))
                        .foregroundStyle(SocialStyle.tertiaryText)
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Estimated one-rep max over \(range.rawValue)")
            .accessibilityValue(accessibilityValue(points))
        }
    }

    private func accessibilityValue(_ points: [ExerciseTrend.Point]) -> String {
        guard let first = points.first, let last = points.last else { return "" }
        return "From \(Int(first.e1rm.rounded())) to \(Int(last.e1rm.rounded())) pounds"
    }
}

/// `1M · 3M · 6M · 1Y · All`: 13pt semibold segments on a dark track.
private struct RangePicker: View {
    @Binding var selection: TrendRange

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TrendRange.allCases) { range in
                let isSelected = range == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = range }
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.systemGray3))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Best set

private struct BestSetCard: View {
    let best: ExerciseTrend.TopSet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Best set")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(ExerciseTrend.formatSet(best))
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
            Text(best.date, format: .dateTime.month(.abbreviated).day().year())
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent sessions

private struct RecentSessionsGroup: View {
    let sessions: [ExerciseTrend.RecentSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("Recent sessions")
                .padding(.leading, 2)
                .padding(.top, 10)
            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    SocialRow(showsSeparator: session.id != sessions.last?.id) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.system(size: 16))
                            Text(subtitle(session))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let e1rm = session.e1rm {
                            Text("e1RM \(Int(e1rm.rounded()))")
                                .font(.system(size: 15).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    /// "3 sets · top 405 × 3".
    private func subtitle(_ session: ExerciseTrend.RecentSession) -> String {
        let sets = "\(session.setCount) set\(session.setCount == 1 ? "" : "s")"
        guard let top = session.topSet else { return sets }
        return "\(sets) · top \(ExerciseTrend.formatSet(top))"
    }
}
