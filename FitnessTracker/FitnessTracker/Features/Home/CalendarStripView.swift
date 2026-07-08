import SwiftUI

/// Horizontal week-paged calendar. Each page shows seven days; swipe left/right
/// to scroll forward/back a week. The page containing today is selected on first
/// appear. Days that have a scheduled workout get a small dot indicator.
///
/// Polish work (month-view zoom, gesture-driven scrubbing, richer accessibility)
/// is tracked in CLAUDE.md → Backlog → Low.
struct CalendarStripView: View {
    @Binding var selectedDate: Date
    let scheduledDateKeys: Set<String>
    let completedDateKeys: Set<String>

    @State private var weekOffset: Int = 0
    @State private var monthSheetPresented = false
    private let calendar: Calendar = .current
    private let pageRange = -52...52  // ~one year either side

    var body: some View {
        VStack(spacing: 4) {
            header

            TabView(selection: $weekOffset) {
                ForEach(pageRange, id: \.self) { offset in
                    weekRow(for: offset)
                        .tag(offset)
                        .padding(.horizontal, 8)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 64)
        }
        .onAppear {
            // Jump to the week containing the currently-selected date.
            weekOffset = weekOffsetForDate(selectedDate)
        }
        // Keep the strip scrolled to the week of the selected date when it
        // changes externally (month sheet pick, jump-to-today).
        .onChange(of: selectedDate) { _, newValue in
            weekOffset = weekOffsetForDate(newValue)
        }
        .sheet(isPresented: $monthSheetPresented) {
            MonthCalendarView(
                selectedDate: $selectedDate,
                scheduledDateKeys: scheduledDateKeys,
                completedDateKeys: completedDateKeys
            )
        }
    }

    // MARK: - Header
    @ViewBuilder
    private var header: some View {
        let weekStart = startOfWeek(weekOffset: weekOffset)
        HStack {
            // Month/year label + caret → opens the full month calendar.
            Button { monthSheetPresented = true } label: {
                HStack(spacing: 4) {
                    Text(monthLabelText(for: weekStart))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open month calendar")

            Spacer()

            // Return-to-today, shown only when browsing a day other than today.
            if !calendar.isDate(selectedDate, inSameDayAs: .now) {
                Button {
                    selectedDate = calendar.startOfDay(for: .now)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Return to today")
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Week row
    private func weekRow(for offset: Int) -> some View {
        let weekStart = startOfWeek(weekOffset: offset)
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { dayIndex in
                let date = calendar.date(byAdding: .day, value: dayIndex, to: weekStart) ?? weekStart
                DayCell(
                    date: date,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(date),
                    hasSchedule: scheduledDateKeys.contains(HomeViewModel.dayKey(date, calendar: calendar)),
                    hasCompleted: isPastDate(date)
                        && completedDateKeys.contains(HomeViewModel.dayKey(date, calendar: calendar))
                ) {
                    selectedDate = calendar.startOfDay(for: date)
                }
            }
        }
    }

    // MARK: - Helpers
    private func startOfWeek(weekOffset: Int) -> Date {
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        let thisWeekStart = calendar.date(byAdding: .day, value: -daysFromWeekStart, to: today) ?? today
        return calendar.date(byAdding: .day, value: weekOffset * 7, to: thisWeekStart) ?? thisWeekStart
    }

    private func weekOffsetForDate(_ date: Date) -> Int {
        let thisWeekStart = startOfWeek(weekOffset: 0)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: thisWeekStart, to: target).day ?? 0
        // Floor toward negative for past dates so e.g. -3 days → previous week (-1).
        return Int((Double(days) / 7.0).rounded(.down))
    }

    private func monthLabelText(for weekStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: weekStart)
    }

    private func isPastDate(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: .now)
    }
}

// MARK: - Day cell
private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasSchedule: Bool
    let hasCompleted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(weekdayLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? Color.white : .secondary)
                Text(dayLabel)
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : .primary)
                Circle()
                    .fill(hasSchedule ? Color.accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Selection is shown with a fill, so no border then. Otherwise today gets an
    /// accent border and a past completed day gets a green border.
    private var borderColor: Color {
        if isSelected { return .clear }
        if isToday { return Color.accentColor.opacity(0.5) }
        if hasCompleted { return Color.green.opacity(0.5) }
        return .clear
    }

    private var weekdayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private var accessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        var label = formatter.string(from: date)
        if hasSchedule { label += ", scheduled workout" }
        if hasCompleted { label += ", completed workout" }
        if isToday { label += ", today" }
        return label
    }
}
