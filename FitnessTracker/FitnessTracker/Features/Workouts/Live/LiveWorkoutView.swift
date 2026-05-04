import SwiftUI

/// Top-level live (in-progress) workout view. Presented as a full-screen
/// cover from RootTabView in response to LiveWorkoutPresentation.isPresented.
///
/// Layout: header (W/D + warm-up + abandon), exercise blocks, notes editor,
/// Add Exercise button, Complete CTA at the bottom. Reuses SetLogSheet from M6.
struct LiveWorkoutView: View {
    @State private var viewModel: LiveWorkoutViewModel
    /// Single source of truth for which sheet (if any) is presented. Stacking
    /// multiple `.sheet` modifiers on one view caused `_UIReparentingView`
    /// warnings when a sheet was presented from a Menu (the dismissal of the
    /// menu and the sheet present overlapped), so we collapse all sheet
    /// presentations into one optional enum + one `.sheet(item:)` modifier.
    @State private var presentedSheet: PresentedSheet?
    @State private var showCompleteConfirmation = false
    @State private var showAbandonConfirmation = false
    @Environment(\.dismiss) private var dismiss

    init(viewModel: LiveWorkoutViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(headerTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .task { await viewModel.load() }
                .sheet(item: $presentedSheet, content: sheetContent(for:))
                .confirmationDialog(
                    "Complete this workout?",
                    isPresented: $showCompleteConfirmation,
                    titleVisibility: .visible,
                    actions: { completeDialogActions },
                    message: { Text("This finalizes your session and advances your program.") }
                )
                .confirmationDialog(
                    "Abandon this workout?",
                    isPresented: $showAbandonConfirmation,
                    titleVisibility: .visible,
                    actions: { abandonDialogActions },
                    message: { Text("All recorded sets for this session will be discarded.") }
                )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.session == nil {
            ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.session == nil {
            ContentUnavailableView(
                "No active workout",
                systemImage: "dumbbell",
                description: Text("Start a workout from the Home tab to begin tracking.")
            )
        } else {
            workoutForm
        }
    }

    private var workoutForm: some View {
        Form {
            if let warmUp = viewModel.day?.warmUp, !warmUp.isEmpty {
                Section("Warm-up") { Text(warmUp) }
            }

            exerciseSections
            adhocSection
            notesSection
            completionSection

            if let actionError = viewModel.actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.footnote) }
            }
        }
    }

    // MARK: - Header

    private var headerTitle: String {
        guard let s = viewModel.session else { return "Workout" }
        return "Week \(s.weekNumber) · Day \(s.dayNumber)"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { presentedSheet = .preview } label: { Label("Preview workout", systemImage: "eye") }
                Button(role: .destructive) {
                    showAbandonConfirmation = true
                } label: {
                    Label("Abandon", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Exercise sections

    @ViewBuilder
    private var exerciseSections: some View {
        if let day = viewModel.day {
            ForEach(day.exerciseGroups, id: \.id) { group in
                Section {
                    ForEach(group.exercises, id: \.id) { exercise in
                        ExerciseCard(
                            viewModel: viewModel,
                            exercise: exercise,
                            onTapTemplateSet: { templateSet in
                                presentedSheet = .setLog(.template(
                                    exerciseName: exercise.exercise.name,
                                    programExerciseId: exercise.id,
                                    templateSet: templateSet
                                ))
                            },
                            onAddExtraSet: {
                                presentedSheet = .setLog(.extra(
                                    exerciseName: exercise.exercise.name,
                                    programExerciseId: exercise.id,
                                    nextSetNumber: exercise.sets.count + viewModel.extraSets(forProgramExerciseId: exercise.id).count + 1
                                ))
                            },
                            onSwap: {
                                presentedSheet = .swap(SwapTarget(programExerciseId: exercise.id, currentName: exercise.exercise.name))
                            },
                            onShowTrend: {
                                presentedSheet = .trend(TrendTarget(exerciseId: exercise.exercise.id, exerciseName: exercise.exercise.name))
                            }
                        )
                    }
                } header: {
                    Text(group.type == .superset ? "Superset" : "Standard")
                }
            }
        }
    }

    // MARK: - Ad-hoc

    @ViewBuilder
    private var adhocSection: some View {
        if !viewModel.adhocSets.isEmpty {
            Section("Ad-hoc") {
                ForEach(viewModel.adhocSets) { set in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.adhocExerciseName ?? "Exercise")
                                .font(.subheadline)
                            if let reps = set.reps, let weight = set.weight {
                                Text("\(reps) reps · \(formatWeight(weight)) lb")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await viewModel.deleteAdHocSet(id: set.id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }

        Section {
            Button { presentedSheet = .adHocSearch } label: {
                Label("Add exercise", systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section {
            TextField("Workout notes", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...6)
            HStack {
                Spacer()
                NotesSaveStatusLabel(state: viewModel.notesSaveState)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Notes")
        }
    }

    // MARK: - Completion

    private var completionSection: some View {
        Section {
            HStack {
                Label("\(viewModel.loggedTemplateSetCount) of \(viewModel.totalTemplateSets) template sets", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                showCompleteConfirmation = true
            } label: {
                HStack {
                    if viewModel.isCompleting { ProgressView().controlSize(.small) }
                    Text(viewModel.isCompleting ? "Completing…" : "Complete workout")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isCompleting)
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(for target: PresentedSheet) -> some View {
        switch target {
        case .setLog(let t): setLogSheet(for: t)
        case .swap(let t): swapSheet(for: t)
        case .trend(let t): trendSheet(for: t)
        case .preview: previewSheet()
        case .adHocSearch: adHocSearchSheet()
        }
    }

    private func setLogSheet(for target: SetEditTarget) -> some View {
        let vm = viewModel
        switch target {
        case .template(let name, _, let templateSet):
            let exerciseSetId = templateSet.id
            let existing = vm.completedSet(forExerciseSetId: exerciseSetId)
            let onSave: (Int?, Double?, Double?, String?) async -> Bool = { reps, weight, rpe, notes in
                await vm.logSet(exerciseSetId: exerciseSetId, reps: reps, weight: weight, rpe: rpe, notes: notes)
            }
            var onDelete: (() async -> Bool)? = nil
            if existing != nil {
                onDelete = { await vm.deleteLoggedSet(exerciseSetId: exerciseSetId) }
            }
            return AnyView(SetLogSheet(
                exerciseName: name,
                setNumber: templateSet.setNumber,
                templateSet: templateSet,
                existing: existing,
                onSave: onSave,
                onDelete: onDelete
            ))
        case .extra(let name, let peId, let nextSetNumber):
            // Synthesize a placeholder template so SetLogSheet has somewhere to draw
            // its placeholders from. The values are nil-only — extra sets have no template.
            let placeholderTemplate = ExerciseSetDTO(
                id: "extra-\(peId)-\(nextSetNumber)",
                programExerciseId: peId, setNumber: nextSetNumber,
                reps: nil, weight: nil, rpe: nil, notes: nil, effortTarget: nil
            )
            let onSave: (Int?, Double?, Double?, String?) async -> Bool = { reps, weight, rpe, notes in
                await vm.addExtraSet(programExerciseId: peId, reps: reps, weight: weight, rpe: rpe, notes: notes)
            }
            return AnyView(SetLogSheet(
                exerciseName: name,
                setNumber: nextSetNumber,
                templateSet: placeholderTemplate,
                existing: nil,
                onSave: onSave,
                onDelete: nil
            ))
        }
    }

    private func swapSheet(for target: SwapTarget) -> some View {
        let vm = viewModel
        return ExerciseSwapSheet(
            programExerciseId: target.programExerciseId,
            currentExerciseName: target.currentName,
            hasLoggedSets: !vm.completedByExerciseSetId.isEmpty || !vm.extraSets(forProgramExerciseId: target.programExerciseId).isEmpty,
            onConfirm: { replacementId in
                let deleted = await vm.swap(programExerciseId: target.programExerciseId, replacementExerciseId: replacementId)
                return deleted
            }
        )
    }

    private func trendSheet(for target: TrendTarget) -> some View {
        ExerciseTrendSheet(exerciseId: target.exerciseId, exerciseName: target.exerciseName)
    }

    private func previewSheet() -> some View {
        WorkoutPreviewSheet(day: viewModel.day)
    }

    private func adHocSearchSheet() -> some View {
        let vm = viewModel
        return ExerciseSearchSheet(
            title: "Add exercise",
            subtitle: "Pick an exercise to log a one-off set."
        ) { exercise in
            await vm.addAdHocExercise(name: exercise.name)
        }
    }

    // MARK: - Dialog actions

    @ViewBuilder
    private var completeDialogActions: some View {
        Button("Complete") {
            Task { if await viewModel.completeWorkout() { dismiss() } }
        }
        Button("Cancel", role: .cancel) { }
    }

    @ViewBuilder
    private var abandonDialogActions: some View {
        Button("Abandon", role: .destructive) {
            Task { if await viewModel.abandonWorkout() { dismiss() } }
        }
        Button("Cancel", role: .cancel) { }
    }

    // MARK: - Helpers

    private func formatWeight(_ value: Double) -> String {
        let f = NumberFormatter()
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - Targets (sheet identifiers)

    /// Single discriminator for `.sheet(item:)`. Keeps `LiveWorkoutView` from
    /// stacking five separate `.sheet` modifiers on one view, which caused
    /// `_UIReparentingView` warnings when sheets were presented from a Menu.
    fileprivate enum PresentedSheet: Identifiable {
        case setLog(SetEditTarget)
        case swap(SwapTarget)
        case trend(TrendTarget)
        case preview
        case adHocSearch

        var id: String {
            switch self {
            case .setLog(let t): return "setLog-\(t.id)"
            case .swap(let t): return "swap-\(t.id)"
            case .trend(let t): return "trend-\(t.id)"
            case .preview: return "preview"
            case .adHocSearch: return "adHocSearch"
            }
        }
    }

    fileprivate enum SetEditTarget: Identifiable {
        case template(exerciseName: String, programExerciseId: String, templateSet: ExerciseSetDTO)
        case extra(exerciseName: String, programExerciseId: String, nextSetNumber: Int)

        var id: String {
            switch self {
            case .template(_, _, let t): return "tpl-\(t.id)"
            case .extra(_, let pe, let n): return "ext-\(pe)-\(n)"
            }
        }
    }

    fileprivate struct SwapTarget: Identifiable {
        let programExerciseId: String
        let currentName: String
        var id: String { programExerciseId }
    }

    fileprivate struct TrendTarget: Identifiable {
        let exerciseId: String
        let exerciseName: String
        var id: String { exerciseId }
    }
}

// MARK: - Notes status label

private struct NotesSaveStatusLabel: View {
    let state: NotesSaveState

    var body: some View {
        switch state {
        case .idle: EmptyView()
        case .pending: Text("Saving…")
        case .saving: Text("Saving…")
        case .saved: Text("Saved")
        case .failed: Text("Save failed").foregroundStyle(.red)
        }
    }
}
