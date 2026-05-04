import SwiftUI

/// "Manage Program" screen — collapsible weeks, status-badged days. Lives
/// inside the Home tab's NavigationStack (entered from the Manage button on
/// the active program card). Tapping a non-locked day pushes a
/// ProgramDayEditView for the retroactive logging / editing flow.
struct ProgramFlowView: View {
    @State private var viewModel: ProgramFlowViewModel
    @State private var expandedWeeks: Set<Int> = []
    private let workoutRepository: WorkoutRepository
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ProgramFlowViewModel, workoutRepository: WorkoutRepository) {
        _viewModel = State(initialValue: viewModel)
        self.workoutRepository = workoutRepository
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.activeProgram == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let program = viewModel.activeProgram {
                content(program: program)
            } else {
                ContentUnavailableView(
                    "No active program",
                    systemImage: "dumbbell",
                    description: Text("Activate a program from the Programs tab to get started.")
                )
            }
        }
        .navigationTitle("Manage Program")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
            // Auto-expand the current week, mirroring the web behavior.
            if let program = viewModel.activeProgram {
                expandedWeeks.insert(program.currentWeek)
            }
        }
        .refreshable { await viewModel.load() }
    }

    private func content(program: ActiveUserProgramDTO) -> some View {
        List {
            Section { Text(program.program.name).foregroundStyle(.secondary) }

            ForEach(program.program.weeks, id: \.id) { week in
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedWeeks.contains(week.weekNumber) },
                            set: { isExpanded in
                                if isExpanded { expandedWeeks.insert(week.weekNumber) }
                                else { expandedWeeks.remove(week.weekNumber) }
                            }
                        )
                    ) {
                        ForEach(week.days, id: \.id) { day in
                            dayRow(weekNumber: week.weekNumber, day: day)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Week \(week.weekNumber)").font(.headline)
                            Spacer()
                            Text("\(week.days.count) days")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func dayRow(weekNumber: Int, day: ProgramDayDTO) -> some View {
        let status = viewModel.status(forWeek: weekNumber, day: day.dayNumber)
        let isLocked = viewModel.isLiveAtCurrentPosition(week: weekNumber, day: day.dayNumber)
        let session = viewModel.sessionFor(week: weekNumber, day: day.dayNumber)

        let label = HStack(spacing: 12) {
            DayStatusBadge(status: status)
            VStack(alignment: .leading, spacing: 2) {
                Text("Day \(day.dayNumber)" + (day.name.map { " — \($0)" } ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(isLocked ? .tertiary : .primary)
                if isLocked {
                    Text("Workout in progress — finish or discard it from the Home tab")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let session = session {
                    Text("\(session.count.completedSets) / \(viewModel.totalSetsFor(week: weekNumber, day: day.dayNumber)) sets")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }

        if isLocked {
            // The text instructs the user to deal with the workout from the
            // Home tab. Make the row act on that instruction by popping back
            // to Home (this view is pushed onto Home's NavigationStack).
            Button {
                dismiss()
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ProgramDayEditView(
                    weekNumber: weekNumber,
                    day: day,
                    existingSessionId: session?.id,
                    repository: workoutRepository,
                    onChange: { Task { await viewModel.load() } }
                )
            } label: {
                label
            }
        }
    }
}

// MARK: - Status badge
private struct DayStatusBadge: View {
    let status: DayStatus

    var body: some View {
        ZStack {
            Circle().fill(background)
                .frame(width: 24, height: 24)
            icon
        }
        // Status is encoded purely visually (color + icon) — collapse the
        // whole badge into a single VoiceOver element with an explicit label
        // so the row text is augmented rather than overridden.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch status {
        case .completed: return "Completed"
        case .inProgress: return "In progress"
        case .current: return "Current"
        case .upcoming: return "Upcoming"
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
        case .inProgress:
            Circle().fill(.orange).frame(width: 8, height: 8)
        case .current:
            Circle().fill(.purple).frame(width: 8, height: 8)
        case .upcoming:
            Circle().fill(.gray).frame(width: 8, height: 8)
        }
    }

    private var background: Color {
        switch status {
        case .completed: return .green.opacity(0.15)
        case .inProgress: return .orange.opacity(0.15)
        case .current: return .purple.opacity(0.15)
        case .upcoming: return .gray.opacity(0.15)
        }
    }
}
