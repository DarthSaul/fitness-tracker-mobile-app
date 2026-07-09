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
    /// Local UI scaffolding for the "Add core" action. There's no server/DTO
    /// concept of a "core" group yet, so this stays in the view for now — once
    /// added, the "Add core" row hides (single Core group per session).
    @State private var showCoreGroup = false
    /// Rest stopwatch — owned here (not in the sheet) so it keeps counting
    /// while the timer drawer is dismissed and reopened.
    @State private var restStopwatch = RestStopwatch()
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
            coreSection
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

    private var headerTitle: String {
        guard let s = viewModel.session else {
            return viewModel.isLoading ? "Workout loading…" : "Workout"
        }
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
        // Rest stopwatch — same icon-button sizing as the trash button. Keep it
        // in its own glass container on iOS 26 with a fixed spacer.
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                presentedSheet = .restTimer
            } label: {
                Image(systemName: "clock")
            }
        }
    }

    private var leadingTitleContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: false)
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

    // MARK: - Exercise sections

    @ViewBuilder
    private var exerciseSections: some View {
        if let day = viewModel.day {
            ForEach(day.exerciseGroups, id: \.id) { group in
                Section {
                    ForEach(Array(group.exercises.enumerated()), id: \.element.id) { index, exercise in
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
                            },
                            restSeconds: restSeconds(at: index, in: group)
                        )
                    }
                } header: {
                    Text(group.type == .superset ? "Superset" : "Standard")
                }
            }
        }
    }

    /// Rest to show on a given exercise's collapsed card. Standard groups show
    /// it on every exercise; supersets show it only on the final exercise,
    /// since rest is taken after the whole superset round.
    private func restSeconds(at index: Int, in group: ExerciseGroupDTO) -> Int? {
        if group.type == .superset && index != group.exercises.count - 1 {
            return nil
        }
        return group.restSeconds
    }

    // MARK: - Core

    /// The "Core" exercise-group button, added on demand from the "Add core"
    /// action. Unlike the exercise-group cards (which expand inline via a
    /// downward chevron), this is a `NavigationLink` — it renders the standard
    /// right-facing disclosure chevron and pushes `CoreView` (slides in from
    /// the right) within the live workout's `NavigationStack`.
    @ViewBuilder
    private var coreSection: some View {
        // Visible once the user taps "Add core" — and stays visible while any
        // core exercises are in the workout (`showCoreGroup` is transient;
        // `addedCoreExercises` is re-seeded from logged core sets on reload).
        if showCoreGroup || !viewModel.addedCoreExercises.isEmpty {
            Section {
                NavigationLink {
                    CoreView(viewModel: viewModel)
                } label: {
                    Text("Core")
                        .font(.headline)
                        .padding(.vertical, 4)
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        }
    }

    // MARK: - Ad-hoc

    @ViewBuilder
    private var adhocSection: some View {
        // Excludes core sets — those render in CoreView, not here, even though
        // both are ad-hoc sets under the hood.
        if !viewModel.adhocSetsExcludingCore.isEmpty {
            Section("Ad-hoc") {
                ForEach(viewModel.adhocSetsExcludingCore) { set in
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

    }

    // MARK: - Actions (Add exercise · Notes · Complete)

    /// The three primary actions collapsed into one contiguous vertical bar —
    /// no inter-section spacing between them. All share the "Add exercise"
    /// layout (leading icon + label); only color/background differs.
    /// "Add exercise" + "Notes" share one inset-grouped card, styled exactly
    /// like the exercise-group cards: default row insets, with the separator
    /// leading guide pinned to 0 so the divider spans the full card width
    /// (the same trick `ExerciseCard` uses).
    private var actionsSection: some View {
        Section {
            actionRow(title: "Add exercise", systemImage: "plus.circle", color: .accentColor) {
                presentedSheet = .adHocSearch
            }
            // "Add core" — same plus icon/accent as "Add exercise". Hidden once
            // the Core group is showing (either just added, or already has core
            // exercises from a prior visit). Single Core group per session.
            if !(showCoreGroup || !viewModel.addedCoreExercises.isEmpty) {
                actionRow(title: "Add core", systemImage: "plus.circle", color: .accentColor) {
                    showCoreGroup = true
                }
            }
            // "Notes" stays in the default primary color (not an accent action).
            actionRow(title: "Notes", systemImage: "note.text", color: .primary) {
                presentedSheet = .workoutNotes
            }
        }
    }

    private func actionRow(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    // MARK: - Completion

    /// Standalone CTA in its own section — keeps the leading icon + label
    /// layout, blue background, and white font from the prominent style.
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
            // Sized to show the header, both fields, and the "Copy previous set"
            // button without scrolling (expandable to large).
            setLogSheet(for: t)
                .presentationDetents([.fraction(0.52), .large])
                .presentationDragIndicator(.visible)
                // Opaque grouped background so the live-workout content behind
                // the drawer doesn't bleed through (the default is translucent).
                .presentationBackground(Color(uiColor: .systemGroupedBackground))
        case .swap(let t): swapSheet(for: t)
        case .trend(let t): trendSheet(for: t)
        case .notes(let t): notesSheet(for: t)
        case .workoutNotes:
            // Starts shorter than the Log-set drawer (.medium); expandable to
            // large for longer notes.
            WorkoutNotesSheet(viewModel: viewModel)
                .presentationDetents([.fraction(0.35), .large])
                .presentationDragIndicator(.visible)
        case .adHocSearch: adHocSearchSheet()
        case .restTimer: RestTimerSheet(stopwatch: restStopwatch)
        }
    }

    private func notesSheet(for target: NotesTarget) -> some View {
        ExerciseNotesSheet(exerciseId: target.exerciseId, exerciseName: target.exerciseName)
    }

    private func setLogSheet(for target: SetEditTarget) -> some View {
        let vm = viewModel
        switch target {
        case .template(let name, let peId, let templateSet):
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
                previousSet: previousSet(forProgramExerciseId: peId, excludingCompletedSetId: existing?.id),
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
                previousSet: previousSet(forProgramExerciseId: peId, excludingCompletedSetId: nil),
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

    /// Values of the most recent set logged for an exercise, for the Log-set
    /// sheet's "Copy previous set" button. Returns nil when nothing's been
    /// logged yet (button hidden). Excludes the set currently being edited.
    private func previousSet(forProgramExerciseId id: String, excludingCompletedSetId: String?) -> PreviousSetValues? {
        let templateSetIds = viewModel.day?.exerciseGroups
            .flatMap(\.exercises)
            .first(where: { $0.id == id })?
            .sets.map(\.id) ?? []
        guard let recent = viewModel.mostRecentLoggedSet(
            programExerciseId: id,
            templateSetIds: templateSetIds,
            excludingCompletedSetId: excludingCompletedSetId
        ) else { return nil }
        return PreviousSetValues(weight: recent.weight)
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
        case workoutNotes
        case adHocSearch
        case restTimer

        var id: String {
            switch self {
            case .setLog(let t): return "setLog-\(t.id)"
            case .swap(let t): return "swap-\(t.id)"
            case .trend(let t): return "trend-\(t.id)"
            case .notes(let t): return "notes-\(t.id)"
            case .workoutNotes: return "workoutNotes"
            case .adHocSearch: return "adHocSearch"
            case .restTimer: return "restTimer"
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

