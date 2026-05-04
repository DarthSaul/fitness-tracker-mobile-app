import SwiftUI

/// Modal that lets the user pick a week/day from the active program to schedule
/// on `viewModel.selectedDate`. Days already completed or already scheduled
/// (anywhere) are surfaced as disabled rows so the user understands why they're
/// unavailable.
struct ScheduleWorkoutSheet: View {
    let viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedWeekNumber: Int
    @State private var pickedDayNumber: Int?

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        // Default to the program's current week — the most relevant view.
        self._selectedWeekNumber = State(initialValue: viewModel.activeProgram?.currentWeek ?? 1)
        self._pickedDayNumber = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Schedule a workout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Schedule") { scheduleAndDismiss() }
                            .disabled(pickedDayNumber == nil)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let program = viewModel.activeProgram {
            VStack(spacing: 0) {
                weekPicker(program: program)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                List {
                    if let week = program.program.weeks.first(where: { $0.weekNumber == selectedWeekNumber }) {
                        Section {
                            ForEach(week.days, id: \.id) { day in
                                dayRow(weekNumber: selectedWeekNumber, day: day)
                            }
                        } header: {
                            Text("For \(formattedTargetDate)")
                        }
                    }
                }
                if let scheduleError = viewModel.scheduleError {
                    Text(scheduleError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
        } else {
            ContentUnavailableView(
                "No active program",
                systemImage: "exclamationmark.triangle",
                description: Text("Activate a program to schedule workouts.")
            )
        }
    }

    private func weekPicker(program: ActiveUserProgramDTO) -> some View {
        Picker("Week", selection: $selectedWeekNumber) {
            ForEach(program.program.weeks, id: \.weekNumber) { week in
                Text("Week \(week.weekNumber)").tag(week.weekNumber)
            }
        }
        .pickerStyle(.segmented)
    }

    private func dayRow(weekNumber: Int, day: ProgramDayDTO) -> some View {
        let isCompleted = viewModel.sessions.contains { s in
            s.weekNumber == weekNumber && s.dayNumber == day.dayNumber && s.status == .completed
        }
        let alreadyScheduled = viewModel.schedule(forWeek: weekNumber, day: day.dayNumber) != nil
        let isPicked = pickedDayNumber == day.dayNumber
        let disabled = isCompleted || alreadyScheduled

        return Button {
            pickedDayNumber = day.dayNumber
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day \(day.dayNumber)" + (day.name.map { " — \($0)" } ?? ""))
                        .foregroundStyle(disabled ? .secondary : .primary)
                    if isCompleted {
                        Text("Completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if alreadyScheduled {
                        Text("Already scheduled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isPicked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var formattedTargetDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: viewModel.selectedDate)
    }

    private func scheduleAndDismiss() {
        guard let dayNumber = pickedDayNumber else { return }
        Task {
            await viewModel.schedule(weekNumber: selectedWeekNumber, dayNumber: dayNumber)
            // Only dismiss on success — schedule errors stay visible in the sheet.
            if viewModel.scheduleError == nil {
                dismiss()
            }
        }
    }
}
