import SwiftUI

/// The History calendar card (design-spec A2): month name and workout count,
/// weekday letters, then a 7-column grid of 30pt day circles. Workout days
/// are tinted blue; the tapped day is solid blue. Swipe sideways to change
/// month.
struct WorkoutMonthCalendarCard: View {
    let workoutCalendar: WorkoutCalendar
    @Binding var displayedMonth: Date
    let selectedDay: Date?
    let onSelectDay: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private var calendar: Calendar { workoutCalendar.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayedMonth, format: monthFormat)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(workoutCalendar.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(SocialStyle.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(workoutCalendar.gridDays(forMonthOf: displayedMonth).enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
        .gesture(monthSwipe)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Previous month") { changeMonth(by: -1) }
        .accessibilityAction(named: "Next month") { changeMonth(by: 1) }
    }

    // MARK: Day cell

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let hasWorkout = workoutCalendar.hasWorkout(on: day)
        let isHighlighted = hasWorkout && selectedDay.map { calendar.isDate(day, inSameDayAs: $0) } == true
        Button {
            onSelectDay(day)
        } label: {
            Text(day, format: .dateTime.day())
                .font(.system(size: 13, weight: hasWorkout ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(hasWorkout ? Color.white : Color.secondary)
                .frame(width: 30, height: 30)
                .background {
                    if hasWorkout {
                        Circle().fill(isHighlighted ? Color.blue : Color.blue.opacity(0.28))
                    }
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!hasWorkout)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(hasWorkout ? "Workout completed" : "")
    }

    private var summary: String {
        let count = workoutCalendar.workoutCount(inMonthOf: displayedMonth)
        return count == 1 ? "1 workout" : "\(count) workouts"
    }

    /// "September", plus the year when it isn't this year.
    private var monthFormat: Date.FormatStyle {
        calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .year)
            ? .dateTime.month(.wide)
            : .dateTime.month(.wide).year()
    }

    // MARK: Month paging

    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                // Ignore vertical drags so the list still scrolls.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                changeMonth(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    private func changeMonth(by months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: displayedMonth) else { return }
        // No paging past the current month.
        guard next <= workoutCalendar.monthStart(for: .now) else { return }
        withAnimation(.snappy(duration: 0.2)) { displayedMonth = next }
    }
}
