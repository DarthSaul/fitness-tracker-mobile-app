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
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .task { await viewModel.load() }
                .sheet(item: $presentedSheet, content: sheetContent(for:))
                // Centered .alert avoids the popover-anchor weirdness that
                // .confirmationDialog gets when it's triggered from inside a
                // toolbar Menu — the Menu has already started dismissing by
                // the time the dialog wants to anchor itself to the trigger.
                .alert("Complete this workout?", isPresented: $showCompleteConfirmation) {
                    completeDialogActions
                } message: {
                    Text("This finalizes your session and advances your program.")
                }
                .alert("Abandon this workout?", isPresented: $showAbandonConfirmation) {
                    abandonDialogActions
                } message: {
                    Text("All recorded sets for this session will be discarded.")
                }
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
            completionSection

            if let actionError = viewModel.actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.footnote) }
            }
        }
    }

    private var progressFraction: Double {
        let total = viewModel.totalTemplateSets
        guard total > 0 else { return 0 }
        return min(1, Double(viewModel.loggedTemplateSetCount) / Double(total))
    }

    // MARK: - Header

    private var headerTitle: String {
        guard let s = viewModel.session else { return "Workout" }
        return "Week \(s.weekNumber) · Day \(s.dayNumber)"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Leading: title as plain text + a short progress bar stacked below.
        // On iOS 26+, hide the shared glass background so the slot reads as
        // text rather than a tappable toolbar control.
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { leadingTitleContent }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { leadingTitleContent }
        }
        // Trailing: Close (text) and Abandon (trash) as two independent
        // toolbar items. iOS 26 auto-merges same-placement items into one
        // glass capsule, so insert a fixed ToolbarSpacer between them to keep
        // each in its own container.
        ToolbarItem(placement: .topBarTrailing) {
            Button("Close") { dismiss() }
        }
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .destructive) {
                showAbandonConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(viewModel.isAbandoning)
        }
    }

    private var leadingTitleContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: false)
            // Linear ProgressView ignores .frame(height:); scaleEffect on Y
            // is the standard trick to make the bar visually thicker.
            ProgressView(value: progressFraction)
                .tint(.green)
                .frame(width: 120)
                .scaleEffect(x: 1, y: 1.5, anchor: .leading)
        }
        .allowsHitTesting(false)
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
                            },
                            onShowNotes: {
                                presentedSheet = .notes(NotesTarget(exerciseId: exercise.exercise.id, exerciseName: exercise.exercise.name))
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

    // MARK: - Completion

    private var completionSection: some View {
        Section {
            Button {
                showCompleteConfirmation = true
            } label: {
                // Text owns the centering via .frame(maxWidth: .infinity); the
                // spinner is a leading overlay so it doesn't share the label's
                // width budget and push the text off-center.
                Text(viewModel.isCompleting ? "Completing…" : "Complete Workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .overlay(alignment: .leading) {
                        if viewModel.isCompleting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 16)
                        }
                    }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isCompleting)
            // Zero row insets so the button extends edge-to-edge.
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(for target: PresentedSheet) -> some View {
        switch target {
        case .setLog(let t):
            // Half-height presentation — the set-log form is small enough that
            // a medium detent keeps the row above visible while editing.
            setLogSheet(for: t)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .swap(let t): swapSheet(for: t)
        case .trend(let t): trendSheet(for: t)
        case .notes(let t): notesSheet(for: t)
        case .adHocSearch: adHocSearchSheet()
        }
    }

    private func notesSheet(for target: NotesTarget) -> some View {
        ExerciseNotesSheet(exerciseId: target.exerciseId, exerciseName: target.exerciseName)
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
            // Scope the destructive-swap warning to THIS exercise's logged sets:
            // the global `completedByExerciseSetId` map covers every exercise in
            // the day, so using it directly would warn even when the user has
            // logged sets on other exercises but not this one.
            hasLoggedSets: hasLoggedSets(forProgramExerciseId: target.programExerciseId),
            onConfirm: { replacementId in
                let deleted = await vm.swap(programExerciseId: target.programExerciseId, replacementExerciseId: replacementId)
                return deleted
            }
        )
    }

    private func trendSheet(for target: TrendTarget) -> some View {
        ExerciseTrendSheet(exerciseId: target.exerciseId, exerciseName: target.exerciseName)
    }

    /// True when the specific programExercise has any logged sets — either a
    /// CompletedSet against one of its template sets, or any extra sets.
    private func hasLoggedSets(forProgramExerciseId id: String) -> Bool {
        let extras = !viewModel.extraSets(forProgramExerciseId: id).isEmpty
        let templateSetIds = viewModel.day?.exerciseGroups
            .flatMap(\.exercises)
            .first(where: { $0.id == id })?
            .sets.map(\.id) ?? []
        let templateLogged = templateSetIds.contains { viewModel.completedSet(forExerciseSetId: $0) != nil }
        return templateLogged || extras
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
        case notes(NotesTarget)
        case adHocSearch

        var id: String {
            switch self {
            case .setLog(let t): return "setLog-\(t.id)"
            case .swap(let t): return "swap-\(t.id)"
            case .trend(let t): return "trend-\(t.id)"
            case .notes(let t): return "notes-\(t.id)"
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

    fileprivate struct NotesTarget: Identifiable {
        let exerciseId: String
        let exerciseName: String
        var id: String { exerciseId }
    }
}

