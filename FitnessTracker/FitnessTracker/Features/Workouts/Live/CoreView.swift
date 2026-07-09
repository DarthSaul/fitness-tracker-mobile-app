import SwiftUI

/// Destination for the "Core" exercise group, pushed from the "Core" row on the
/// live workout screen.
///
/// Two areas:
/// - **Setup** — a Time / Rest config row + an "Add core exercise" button that
///   opens a picker of the server core-exercise catalog.
/// - **Your core workout** — the picked exercises (leading circled badges),
///   followed by standalone Save / Start actions.
///
/// The circuit is server-backed: "Save" persists it (PUT) and locks the view;
/// "Start" runs a client-side interval timer and, on natural finish, marks the
/// saved circuit complete.
struct CoreView: View {
    /// Read-only reference to the parent VM (same pattern as `ExerciseCard`).
    let viewModel: LiveWorkoutViewModel

    /// Whether the "Add core exercise" picker sheet is showing.
    @State private var showAddExercise = false
    /// The running core-workout timer, if "Start" was pressed.
    @State private var runningTimer: CoreWorkoutTimer?

    /// Catalog exercises not yet added — what the picker offers.
    private var availableExercises: [ExerciseDTO] {
        viewModel.coreCatalog.filter { candidate in
            !viewModel.coreSelectedExercises.contains { $0.id == candidate.id }
        }
    }

    /// A circuit is runnable/saveable with at least one exercise and a positive
    /// work time.
    private var isCoreConfigured: Bool {
        !viewModel.coreSelectedExercises.isEmpty && viewModel.coreTimeSeconds > 0
    }

    var body: some View {
        Form {
            Section("Setup") {
                setupConfigRow
                addCoreButton
            }

            Section {
                if viewModel.coreSelectedExercises.isEmpty {
                    Text("No core exercises yet. Tap \u{201C}Add core exercise\u{201D} to build your core workout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.coreSelectedExercises.enumerated()), id: \.element.id) { index, exercise in
                        coreExercise(exercise, number: index + 1)
                    }
                }
            } header: {
                HStack {
                    Text("Your core workout")
                    Spacer()
                    if let estimate = viewModel.coreEstimatedSeconds {
                        Text(formatEstimate(estimate))
                    }
                }
            }
            .textCase(nil)
            .listSectionSpacing(16)

            actionButtons

            if let actionError = viewModel.actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Core")
        .navigationBarTitleDisplayMode(.inline)
        // Custom principal title so it can carry the Beta tag (navigationTitle
        // takes a plain String). navigationTitle stays for back-button labeling.
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text("Core").font(.headline)
                    BetaTag()
                }
            }
        }
        .task { await viewModel.loadCoreCatalog() }
        .sheet(isPresented: $showAddExercise) {
            CoreExercisePickerSheet(available: availableExercises) { exercise in
                viewModel.addCoreExercise(exercise)
            }
        }
        .fullScreenCover(item: $runningTimer) { timer in
            CoreTimerView(timer: timer) { finished in
                runningTimer = nil
                if finished {
                    Task { await viewModel.completeCoreWorkoutIfNeeded() }
                }
            }
        }
    }

    // MARK: - Setup

    /// Time / Rest inputs (both seconds), styled with the shared boxed field.
    /// The number of sets is the count of added exercises. Frozen once locked.
    private var setupConfigRow: some View {
        HStack(alignment: .top, spacing: 12) {
            LabeledField(label: "Time (s)") {
                TextField("0", text: bindingFor(\.coreSetupTimeText))
                    .keyboardType(.numberPad)
                    .boxedField()
            }
            LabeledField(label: "Rest (s)") {
                TextField("0", text: bindingFor(\.coreSetupRestText))
                    .keyboardType(.numberPad)
                    .boxedField()
            }
        }
        .disabled(viewModel.isCoreWorkoutLocked)
    }

    private func bindingFor(_ keyPath: ReferenceWritableKeyPath<LiveWorkoutViewModel, String>) -> Binding<String> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    /// "Add core exercise" — styled like `LiveWorkoutView.actionRow`. Disabled
    /// once every catalog exercise is added or the workout is locked.
    private var addCoreButton: some View {
        let disabled = availableExercises.isEmpty || viewModel.isCoreWorkoutLocked
        return Button {
            showAddExercise = true
        } label: {
            Label("Add core exercise", systemImage: "plus.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary : Color.accentColor)
        .disabled(disabled)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    // MARK: - Your core workout

    /// One added core exercise: a leading circled position badge, its name, and a
    /// remove control that hides once the workout is locked.
    @ViewBuilder
    private func coreExercise(_ exercise: ExerciseDTO, number: Int) -> some View {
        HStack(spacing: 12) {
            numberBadge(number)
            Text(exercise.name)
                .font(.headline)
            Spacer()
            if !viewModel.isCoreWorkoutLocked {
                Button(role: .destructive) {
                    viewModel.removeCoreExercise(exercise)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// The exercise's 1-based position as a filled circle badge with a white
    /// number, sitting just before the name.
    private func numberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.accentColor))
    }

    // MARK: - Save / Start

    /// Standalone, full-width Save + Start actions — styled like the main
    /// workout's "Complete Workout" CTA. A muted hint sits under Start while it's
    /// disabled.
    private var actionButtons: some View {
        Section {
            VStack(spacing: 12) {
                saveEditButton
                startButton
                if !isCoreConfigured {
                    Text("Add at least one exercise to start.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// "Save" persists the circuit and locks it; once locked it becomes "Edit",
    /// which unlocks for further changes (no network call).
    private var saveEditButton: some View {
        Button {
            if viewModel.isCoreWorkoutLocked {
                viewModel.isCoreWorkoutLocked = false
            } else {
                Task { await viewModel.saveCoreWorkout() }
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSavingCore { ProgressView().controlSize(.small) }
                Text(saveEditTitle)
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(saveEditDisabled)
    }

    private var saveEditTitle: String {
        if viewModel.isCoreWorkoutLocked { return "Edit" }
        return viewModel.isSavingCore ? "Saving\u{2026}" : "Save"
    }

    /// "Edit" is always tappable; "Save" needs a valid, non-in-flight circuit.
    private var saveEditDisabled: Bool {
        if viewModel.isCoreWorkoutLocked { return false }
        return !isCoreConfigured || viewModel.isSavingCore
    }

    /// "Start" — launches the interval timer. Disabled until there's at least one
    /// exercise and a positive work time.
    private var startButton: some View {
        Button {
            startCoreWorkout()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text("Start")
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.green)
        .disabled(!isCoreConfigured)
    }

    private func startCoreWorkout() {
        let timer = CoreWorkoutTimer(
            sets: viewModel.coreSelectedExercises.count,
            workSeconds: viewModel.coreTimeSeconds,
            restSeconds: viewModel.coreRestSeconds,
            exercises: viewModel.coreSelectedExercises.map(\.name)
        )
        guard !timer.phases.isEmpty else { return }
        runningTimer = timer
    }

    // MARK: - Helpers

    /// Formats a duration in seconds as "m:ss min" (e.g. 360 → "6:00 min").
    private func formatEstimate(_ seconds: Int) -> String {
        String(format: "%d:%02d min", seconds / 60, seconds % 60)
    }
}

// MARK: - Core exercise picker

/// Swipe-up picker for adding a core exercise, mirroring `ExerciseSearchSheet`'s
/// structure (NavigationStack + inline title + Cancel) but backed by the fetched
/// core-exercise catalog instead of a server search.
private struct CoreExercisePickerSheet: View {
    /// Catalog exercises available to add (catalog minus already-added).
    let available: [ExerciseDTO]
    let onPick: (ExerciseDTO) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Pick a core exercise to add.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if available.isEmpty {
                    Text("No core exercises available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(available) { exercise in
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            Text(exercise.name).foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add core exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
