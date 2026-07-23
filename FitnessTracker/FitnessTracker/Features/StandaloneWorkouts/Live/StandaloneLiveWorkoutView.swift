import SwiftUI

/// Live (in-progress) standalone workout view. Presented as a full-screen
/// cover from RootTabView when LiveWorkoutPresentation.target is
/// `.standalone(sessionId:)`. Mirrors LiveWorkoutView's layout — toolbar
/// title + progress, exercise-group sections, ad-hoc section, actions,
/// Complete CTA, bottom close/rest-timer bar — and reuses the same sheets
/// (SetLogSheet, ExerciseSearchSheet, trend/notes, rest timer).
struct StandaloneLiveWorkoutView: View {
    @State private var viewModel: StandaloneLiveWorkoutViewModel
    /// Single source of truth for which sheet (if any) is presented — same
    /// single-`.sheet(item:)` pattern as LiveWorkoutView (stacked `.sheet`
    /// modifiers caused `_UIReparentingView` warnings there).
    @State private var presentedSheet: PresentedSheet?
    @State private var showCompleteConfirmation = false
    @State private var showAbandonConfirmation = false
    /// Rest stopwatch — owned here (not in the sheet) so it keeps counting
    /// while the timer drawer is dismissed and reopened.
    @State private var restStopwatch = RestStopwatch()
    @Environment(\.dismiss) private var dismiss

    init(viewModel: StandaloneLiveWorkoutViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .task { await viewModel.load() }
                .sheet(item: $presentedSheet, content: sheetContent(for:))
                .alert("Complete this workout?", isPresented: $showCompleteConfirmation) {
                    completeDialogActions
                } message: {
                    Text("This finalizes your session. It won't affect your program.")
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
                description: Text(viewModel.loadError ?? "This session is no longer available.")
            )
        } else {
            workoutForm
        }
    }

    private var workoutForm: some View {
        Form {
            exerciseSections
            adhocSection
            actionsSection
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
            Text(viewModel.workoutDisplayName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Progress")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                // Linear ProgressView ignores .frame(height:); scaleEffect on Y
                // is the standard trick to make the bar visually thicker.
                ProgressView(value: progressFraction)
                    .tint(.green)
                    .frame(width: 120)
                    .scaleEffect(x: 1, y: 1.5, anchor: .leading)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Bottom bar

    /// Custom bottom bar via `.safeAreaInset` — same construction as
    /// LiveWorkoutView's (a UIKit `.bottomBar` toolbar is unsupported in this
    /// fullScreenCover + NavigationStack hosting context).
    private var bottomBar: some View {
        Group {
            if #available(iOS 26.0, *) {
                bottomBarStack.buttonStyle(.glass)
            } else {
                bottomBarStack
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .systemBackground).opacity(0.75)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) { Divider() }
    }

    private var bottomBarStack: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Button {
                presentedSheet = .restTimer
            } label: {
                Image(systemName: "clock")
            }
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .imageScale(.large)
        .font(.title2)
    }

    // MARK: - Exercise sections

    @ViewBuilder
    private var exerciseSections: some View {
        if let workout = viewModel.workout {
            ForEach(workout.groups, id: \.id) { group in
                Section {
                    ForEach(Array(group.exercises.enumerated()), id: \.element.id) { index, exercise in
                        StandaloneExerciseCard(
                            viewModel: viewModel,
                            exercise: exercise,
                            onTapTemplateSet: { templateSet in
                                presentedSheet = .setLog(.template(
                                    exerciseName: exercise.exercise.name,
                                    exerciseId: exercise.id,
                                    templateSet: templateSet
                                ))
                            },
                            onAddExtraSet: {
                                presentedSheet = .setLog(.extra(
                                    exerciseName: exercise.exercise.name,
                                    exerciseId: exercise.id,
                                    nextSetNumber: exercise.sets.count
                                        + viewModel.extraSets(forExerciseName: exercise.exercise.name).count + 1
                                ))
                            },
                            onShowTrend: {
                                presentedSheet = .trend(SheetTarget(exerciseId: exercise.exercise.id, exerciseName: exercise.exercise.name))
                            },
                            onShowNotes: {
                                presentedSheet = .notes(SheetTarget(exerciseId: exercise.exercise.id, exerciseName: exercise.exercise.name))
                            },
                            restSeconds: restSeconds(at: index, in: group)
                        )
                    }
                } header: {
                    Text(groupHeader(for: group))
                }
            }
        }
    }

    /// Group label wins when present (e.g. "Cardio"); otherwise the type.
    private func groupHeader(for group: StandaloneWorkoutGroupDTO) -> String {
        if let label = group.label, !label.isEmpty { return label }
        return group.type == .superset ? "Superset" : "Standard"
    }

    /// Rest to show on a given exercise's collapsed card. Standard groups show
    /// it on every exercise; supersets show it only on the final exercise,
    /// since rest is taken after the whole superset round.
    private func restSeconds(at index: Int, in group: StandaloneWorkoutGroupDTO) -> Int? {
        if group.type == .superset && index != group.exercises.count - 1 {
            return nil
        }
        return group.restSeconds
    }

    // MARK: - Ad-hoc

    /// Off-plan sets whose name doesn't match a template exercise (same-named
    /// ad-hoc sets render as extra rows inside the matching card instead).
    @ViewBuilder
    private var adhocSection: some View {
        let unmatched = viewModel.unmatchedAdhocSets
        if !unmatched.isEmpty {
            Section("Ad-hoc") {
                ForEach(unmatched) { set in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.adhocExerciseName ?? "Exercise")
                                .font(.subheadline)
                            if let reps = set.reps, let weight = set.weight {
                                Text("\(reps) reps · \(formatDouble(weight)) lb")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await viewModel.deleteAdhocSet(id: set.id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                presentedSheet = .adHocSearch
            } label: {
                Label("Add exercise", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    // MARK: - Completion

    /// Standalone CTA in its own section — same styling as the program flow's.
    private var completionSection: some View {
        Section {
            Button {
                showCompleteConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                    Text(viewModel.isCompleting ? "Completing…" : "Complete Workout")
                        .foregroundStyle(.white)
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
                .overlay(alignment: .trailing) {
                    if viewModel.isCompleting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isCompleting)
            // Edge-to-edge standalone button (not part of the card above).
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
            setLogSheet(for: t)
                .presentationDetents([.fraction(0.52), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(uiColor: .systemGroupedBackground))
        case .trend(let t):
            ExerciseTrendSheet(exerciseId: t.exerciseId, exerciseName: t.exerciseName)
        case .notes(let t):
            ExerciseNotesSheet(exerciseId: t.exerciseId, exerciseName: t.exerciseName)
        case .adHocSearch:
            adHocSearchSheet()
        case .restTimer:
            RestTimerSheet(stopwatch: restStopwatch)
        }
    }

    private func setLogSheet(for target: SetEditTarget) -> some View {
        let vm = viewModel
        switch target {
        case .template(let name, _, let templateSet):
            let templateSetId = templateSet.id
            let existing = vm.completedSet(forTemplateSetId: templateSetId)
            let onSave: (Int?, Double?, Double?, String?) async -> Bool = { reps, weight, rpe, notes in
                await vm.logSet(templateSetId: templateSetId, reps: reps, weight: weight, rpe: rpe, notes: notes)
            }
            var onDelete: (() async -> Bool)? = nil
            if existing != nil {
                onDelete = { await vm.deleteLoggedSet(templateSetId: templateSetId) }
            }
            return AnyView(SetLogSheet(
                exerciseName: name,
                setNumber: templateSet.setNumber,
                templateSet: placeholderTemplate(from: templateSet),
                existing: completedSetForSheet(existing),
                previousSet: previousSet(forExerciseName: name, excludingCompletedSetId: existing?.id),
                onSave: onSave,
                onDelete: onDelete
            ))
        case .extra(let name, let exerciseId, let nextSetNumber):
            // Synthesize a value-free placeholder template — extra sets have no
            // prescription (same trick as the program flow).
            let placeholder = ExerciseSetDTO(
                id: "extra-\(exerciseId)-\(nextSetNumber)",
                programExerciseId: exerciseId, setNumber: nextSetNumber,
                reps: nil, weight: nil, rpe: nil, notes: nil, effortTarget: nil
            )
            let onSave: (Int?, Double?, Double?, String?) async -> Bool = { reps, weight, rpe, notes in
                await vm.addExtraSet(exerciseName: name, reps: reps, weight: weight, rpe: rpe, notes: notes)
            }
            return AnyView(SetLogSheet(
                exerciseName: name,
                setNumber: nextSetNumber,
                templateSet: placeholder,
                existing: nil,
                previousSet: previousSet(forExerciseName: name, excludingCompletedSetId: nil),
                onSave: onSave,
                onDelete: nil
            ))
        }
    }

    /// SetLogSheet takes the program-flow DTO types; bridge the standalone
    /// template set into an `ExerciseSetDTO` (ids are only used for display
    /// defaults inside the sheet, never sent back to the server).
    private func placeholderTemplate(from set: StandaloneWorkoutSetDTO) -> ExerciseSetDTO {
        ExerciseSetDTO(
            id: set.id,
            programExerciseId: set.standaloneWorkoutExerciseId,
            setNumber: set.setNumber,
            reps: set.reps, weight: set.weight, rpe: set.rpe,
            notes: set.notes, effortTarget: set.effortTarget
        )
    }

    /// Same bridge for the logged set — the sheet only reads reps/weight for
    /// prefill and non-nilness for its Edit/Delete affordances.
    private func completedSetForSheet(_ set: StandaloneCompletedSetDTO?) -> CompletedSetDTO? {
        guard let set else { return nil }
        return CompletedSetDTO(
            id: set.id,
            workoutSessionId: set.standaloneWorkoutSessionId,
            exerciseSetId: set.standaloneWorkoutSetId,
            programExerciseId: nil,
            adhocExerciseName: set.adhocExerciseName,
            reps: set.reps, weight: set.weight, rpe: set.rpe,
            notes: set.notes, completedAt: set.completedAt
        )
    }

    /// Values of the most recent set logged for an exercise, for the Log-set
    /// sheet's "Copy previous set" button. Excludes the set being edited.
    private func previousSet(forExerciseName name: String, excludingCompletedSetId: String?) -> PreviousSetValues? {
        let templateSetIds = viewModel.workout?.groups
            .flatMap(\.exercises)
            .first(where: { $0.exercise.name == name })?
            .sets.map(\.id) ?? []
        guard let recent = viewModel.mostRecentLoggedSet(
            exerciseName: name,
            templateSetIds: templateSetIds,
            excludingCompletedSetId: excludingCompletedSetId
        ) else { return nil }
        return PreviousSetValues(weight: recent.weight)
    }

    private func adHocSearchSheet() -> some View {
        let vm = viewModel
        return ExerciseSearchSheet(
            title: "Add exercise",
            subtitle: "Pick an exercise to log a one-off set."
        ) { exercise in
            await vm.addAdhocExercise(name: exercise.name)
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

    // MARK: - Targets (sheet identifiers)

    fileprivate enum PresentedSheet: Identifiable {
        case setLog(SetEditTarget)
        case trend(SheetTarget)
        case notes(SheetTarget)
        case adHocSearch
        case restTimer

        var id: String {
            switch self {
            case .setLog(let t): return "setLog-\(t.id)"
            case .trend(let t): return "trend-\(t.id)"
            case .notes(let t): return "notes-\(t.id)"
            case .adHocSearch: return "adHocSearch"
            case .restTimer: return "restTimer"
            }
        }
    }

    fileprivate enum SetEditTarget: Identifiable {
        case template(exerciseName: String, exerciseId: String, templateSet: StandaloneWorkoutSetDTO)
        case extra(exerciseName: String, exerciseId: String, nextSetNumber: Int)

        var id: String {
            switch self {
            case .template(_, _, let t): return "tpl-\(t.id)"
            case .extra(_, let exerciseId, let n): return "ext-\(exerciseId)-\(n)"
            }
        }
    }

    fileprivate struct SheetTarget: Identifiable {
        let exerciseId: String
        let exerciseName: String
        var id: String { exerciseId }
    }
}
