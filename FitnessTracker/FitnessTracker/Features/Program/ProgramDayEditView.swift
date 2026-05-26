import SwiftUI

/// Retroactive day-edit screen. Two states:
///   - No session yet → "Start logging" CTA + day preview.
///   - EDITING session present → date picker + per-set rows that open SetLogSheet,
///     plus Save (complete with backdate) and Discard (abandon) actions.
struct ProgramDayEditView: View {
    @State private var viewModel: ProgramDayEditViewModel
    @State private var setBeingEdited: SetEditTarget?
    @State private var showDiscardConfirmation = false
    @State private var showSaveConfirmation = false
    @Environment(\.dismiss) private var dismiss

    init(
        weekNumber: Int,
        day: ProgramDayDTO,
        existingSessionId: String?,
        repository: WorkoutRepository,
        onChange: @escaping () -> Void
    ) {
        let vm = ProgramDayEditViewModel(
            weekNumber: weekNumber,
            day: day,
            existingSessionId: existingSessionId,
            repository: repository,
            onChange: onChange
        )
        _viewModel = State(initialValue: vm)
    }

    var body: some View {
        formContent
            .navigationTitle("Week \(viewModel.weekNumber), Day \(viewModel.day.dayNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { trashToolbar }
            .task { await viewModel.loadIfNeeded() }
            .sheet(item: $setBeingEdited, content: setLogSheet(for:))
            .confirmationDialog(
                "Discard this session?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible,
                actions: { discardDialogActions },
                message: { Text("All logged sets for this session will be removed. This can't be undone.") }
            )
            .confirmationDialog(
                "Save this workout?",
                isPresented: $showSaveConfirmation,
                titleVisibility: .visible,
                actions: { saveDialogActions },
                message: { Text(saveDialogMessage) }
            )
    }

    private var formContent: some View {
        Form {
            if viewModel.isLoading && viewModel.session == nil {
                // Distinct from the empty state: an existing-session fetch is
                // in-flight. Showing the Start CTA here would race with
                // loadIfNeeded() and risk a duplicate session creation.
                Section {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading session…").foregroundStyle(.secondary)
                    }
                }
            } else if viewModel.session == nil {
                emptyStateSection
            } else {
                datePickerSection
                exerciseSections
                actionsSection
            }
            if let loadError = viewModel.loadError {
                Section {
                    Text(loadError).foregroundStyle(.red).font(.footnote)
                }
            }
            if let actionError = viewModel.actionError {
                Section {
                    Text(actionError).foregroundStyle(.red).font(.footnote)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var trashToolbar: some ToolbarContent {
        if viewModel.session != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDiscardConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.isAbandoning)
            }
        }
    }

    @ViewBuilder
    private var discardDialogActions: some View {
        Button("Discard", role: .destructive) {
            Task { if await viewModel.discard() { dismiss() } }
        }
        Button("Cancel", role: .cancel) { }
    }

    @ViewBuilder
    private var saveDialogActions: some View {
        Button("Save") {
            Task { if await viewModel.completeWithBackdate() { dismiss() } }
        }
        Button("Cancel", role: .cancel) { }
    }

    private func setLogSheet(for target: SetEditTarget) -> some View {
        let exerciseSetId = target.templateSet.id
        let existing = viewModel.completedSet(forExerciseSetId: exerciseSetId)
        let vm = viewModel
        let onSave: (Int?, Double?, Double?, String?) async -> Bool = { reps, weight, rpe, notes in
            await vm.logSet(
                exerciseSetId: exerciseSetId,
                reps: reps, weight: weight, rpe: rpe, notes: notes
            )
        }
        var onDelete: (() async -> Bool)? = nil
        if existing != nil {
            onDelete = {
                await vm.deleteLoggedSet(exerciseSetId: exerciseSetId)
            }
        }
        return SetLogSheet(
            exerciseName: target.exerciseName,
            setNumber: target.templateSet.setNumber,
            templateSet: target.templateSet,
            existing: existing,
            onSave: onSave,
            onDelete: onDelete
        )
    }

    // MARK: - Sections

    private var emptyStateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("No session yet")
                    .font(.headline)
                Text("Start logging to record this workout retroactively. The session will be marked Editing until you save.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await viewModel.startRetroactive() }
            } label: {
                HStack {
                    if viewModel.isStartingSession { ProgressView().controlSize(.small) }
                    Text(viewModel.isStartingSession ? "Starting…" : "Start logging")
                }
            }
            .buttonStyle(.borderedProminent)
            // Disabled during initial load too, defensively — formContent's
            // loading branch normally hides this section while isLoading,
            // but lock the action regardless in case the state ever races.
            .disabled(viewModel.isStartingSession || viewModel.isLoading)
        }
    }

    private var datePickerSection: some View {
        Section("Workout date") {
            DatePicker(
                "Date",
                selection: $viewModel.workoutDate,
                in: ...Date.now,
                displayedComponents: .date
            )
        }
    }

    private var exerciseSections: some View {
        ForEach(viewModel.day.exerciseGroups, id: \.id) { group in
            Section {
                ForEach(group.exercises, id: \.id) { exercise in
                    ExerciseBlock(
                        exercise: exercise,
                        completedByExerciseSetId: viewModel.completedByExerciseSetId,
                        onTapSet: { set in
                            setBeingEdited = SetEditTarget(exerciseName: exercise.exercise.name, templateSet: set)
                        }
                    )
                }
            } header: {
                Text(group.type == .superset ? "Superset" : "Standard")
            }
        }
    }

    private var actionsSection: some View {
        Section {
            HStack {
                Label("\(viewModel.loggedSetsCount) of \(viewModel.totalTemplateSets) sets logged", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                showSaveConfirmation = true
            } label: {
                HStack {
                    if viewModel.isCompleting { ProgressView().controlSize(.small) }
                    Text(viewModel.isCompleting ? "Saving…" : "Save workout")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isCompleting || viewModel.loggedSetsCount == 0)
        }
    }

    // MARK: - Helpers

    private var formattedWorkoutDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: viewModel.workoutDate)
    }

    private var saveDialogMessage: String {
        if viewModel.session?.status == .completed {
            return "This updates the workout date to \(formattedWorkoutDate)."
        }
        return "This marks the workout complete on \(formattedWorkoutDate)."
    }

    fileprivate struct SetEditTarget: Identifiable {
        let exerciseName: String
        // Property is named `templateSet` rather than `set` because Swift's
        // accessor parser would interpret `var id: String { set.id }` as a
        // setter declaration, not a member access.
        let templateSet: ExerciseSetDTO
        var id: String { templateSet.id }
    }
}

// MARK: - Exercise block
private struct ExerciseBlock: View {
    let exercise: ProgramExerciseDTO
    let completedByExerciseSetId: [String: CompletedSetDTO]
    let onTapSet: (ExerciseSetDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.exercise.name)
                .font(.headline)
            ForEach(exercise.sets, id: \.id) { templateSet in
                SetRow(
                    templateSet: templateSet,
                    completed: completedByExerciseSetId[templateSet.id],
                    onTap: { onTapSet(templateSet) }
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SetRow: View {
    let templateSet: ExerciseSetDTO
    let completed: CompletedSetDTO?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("Set \(templateSet.setNumber)")
                    .foregroundStyle(.primary)
                Spacer()
                summaryText
                Image(systemName: completed == nil ? "plus.circle" : "checkmark.circle.fill")
                    .foregroundStyle(completed == nil ? Color.secondary : Color.green)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var summaryText: some View {
        if let completed {
            Text(formatSet(reps: completed.reps, weight: completed.weight, rpe: completed.rpe))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.green)
        } else {
            Text(formatSet(reps: templateSet.reps, weight: templateSet.weight, rpe: templateSet.rpe))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private func formatSet(reps: Int?, weight: Double?, rpe: Double?) -> String {
        var parts: [String] = []
        if let reps { parts.append("\(reps) reps") }
        if let weight { parts.append("\(formatDouble(weight)) lb") }
        if let rpe { parts.append("RPE \(formatDouble(rpe))") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func formatDouble(_ value: Double) -> String {
        let f = NumberFormatter()
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
