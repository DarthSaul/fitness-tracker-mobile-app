import SwiftUI

/// Full-month calendar grid presented as a sheet from `CalendarStripView`.
/// Lets the user navigate month-by-month and pick any day; mirrors the strip's
/// visual language (accent fill for the selected day, accent border for today,
/// and an accent dot for days with a scheduled workout). Picking a day updates
/// the bound `selectedDate` and dismisses.
struct MonthCalendarView: View {
    @Binding var selectedDate: Date
    let scheduledDateKeys: Set<String>
    let completedDateKeys: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth: Date
    /// Measured height of the calendar content, used to size the sheet so it
    /// hugs the grid instead of leaving deadspace under a fixed `.medium` detent.
    /// Seeded with a sensible default to avoid a zero-height first frame.
    @State private var contentHeight: CGFloat = 420
    /// Direction the grid slides when the month changes, so swipe/chevron
    /// navigation animates toward the newly-shown month.
    @State private var slideEdge: Edge = .trailing
    private let calendar: Calendar = .current

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    init(selectedDate: Binding<Date>, scheduledDateKeys: Set<String>, completedDateKeys: Set<String>) {
        _selectedDate = selectedDate
        self.scheduledDateKeys = scheduledDateKeys
        self.completedDateKeys = completedDateKeys
        let cal = Calendar.current
        let monthStart = cal.dateInterval(of: .month, for: selectedDate.wrappedValue)?.start
            ?? cal.startOfDay(for: selectedDate.wrappedValue)
        _displayedMonth = State(initialValue: monthStart)
    }

    var body: some View {
        VStack(spacing: 16) {
            monthHeader
            weekdayHeader
            monthGrid
        }
        .padding()
        .contentShape(Rectangle())
        .gesture(monthSwipe)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, height in
                        contentHeight = height
                    }
            }
        }
        .presentationDetents([.height(contentHeight)])
    }

    /// Horizontal swipe to page between months. Ignores vertical-dominant drags
    /// so the sheet's own swipe-to-dismiss keeps working.
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy), abs(dx) > 40 else { return }
                stepMonth(dx < 0 ? 1 : -1)  // swipe left → next, right → previous
            }
    }

    // MARK: - Month header (title + prev/next)
    private var monthHeader: some View {
        HStack {
            Button { stepMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()

            HStack(spacing: 6) {
                Text(monthTitle)
                    .font(.headline)
                // Return-to-current-month, shown only when browsing another month.
                if !isViewingCurrentMonth {
                    Button {
                        setDisplayedMonth(currentMonthStart)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Return to current month")
                }
            }

            Spacer()

            Button { stepMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
        }
        .padding(.top, 8)
    }

    // MARK: - Weekday header
    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid
    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(for: day)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .id(displayedMonth)
        .transition(.asymmetric(
            insertion: .move(edge: slideEdge),
            removal: .move(edge: slideEdge == .trailing ? .leading : .trailing)
        ))
    }

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let dayKey = HomeViewModel.dayKey(date, calendar: calendar)
        let hasSchedule = scheduledDateKeys.contains(dayKey)
        let hasCompleted = isPastDate(date) && completedDateKeys.contains(dayKey)

        Button {
            selectedDate = calendar.startOfDay(for: date)
            dismiss()
        } label: {
            VStack(spacing: 2) {
                Text(dayLabel(for: date))
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : .primary)
                Circle()
                    .fill(hasSchedule ? Color.accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor(isSelected: isSelected, isToday: isToday, hasCompleted: hasCompleted), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date, hasSchedule: hasSchedule, hasCompleted: hasCompleted, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Helpers
    private func stepMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        setDisplayedMonth(next)
    }

    /// Animates to `target`, sliding toward it (later month → in from the trailing
    /// edge, earlier month → in from the leading edge).
    private func setDisplayedMonth(_ target: Date) {
        slideEdge = target >= displayedMonth ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.25)) {
            displayedMonth = target
        }
    }

    /// Start of the month containing today, used as the return-to-current-month target.
    private var currentMonthStart: Date {
        calendar.dateInterval(of: .month, for: .now)?.start ?? calendar.startOfDay(for: .now)
    }

    private var isViewingCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month)
    }

    private func isPastDate(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: .now)
    }

    /// Selection is shown with a fill, so no border then. Otherwise today gets an
    /// accent border and a past completed day gets a green border.
    private func borderColor(isSelected: Bool, isToday: Bool, hasCompleted: Bool) -> Color {
        if isSelected { return .clear }
        if isToday { return Color.accentColor.opacity(0.5) }
        if hasCompleted { return Color.green.opacity(0.5) }
        return .clear
    }

    /// Fixed number of cells: 6 weeks × 7 days. Padding every month to a full
    /// 6-row grid keeps the sheet height constant when paging between 5- and
    /// 6-week months (max real span is 37 cells, so this never truncates).
    private static let cellCount = 42

    /// Cells for the displayed month: leading `nil`s pad the first week so the
    /// 1st lands under its weekday column, one date per day, then trailing
    /// `nil`s pad out to a constant 6-row grid.
    private var monthCells: [Date?] {
        guard
            let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start,
            let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth)
        else { return Array(repeating: nil, count: Self.cellCount) }

        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                cells.append(date)
            }
        }
        if cells.count < Self.cellCount {
            cells.append(contentsOf: Array(repeating: nil, count: Self.cellCount - cells.count))
        }
        return cells
    }

    /// `shortWeekdaySymbols` rotated to start at the calendar's `firstWeekday`.
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func accessibilityLabel(for date: Date, hasSchedule: Bool, hasCompleted: Bool, isToday: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        var label = formatter.string(from: date)
        if hasSchedule { label += ", scheduled workout" }
        if hasCompleted { label += ", completed workout" }
        if isToday { label += ", today" }
        return label
    }
}
