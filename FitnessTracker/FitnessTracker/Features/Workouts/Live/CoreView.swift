import SwiftUI

/// Destination for the "Core" exercise group, pushed from the "Core" row on the
/// live workout screen.
///
/// Two areas:
/// - **Setup** — a Sets / Time / Rest config row (drives the estimated duration)
///   and an "Add core exercise" button that opens a picker (the fixed
///   `CoreExercise.defaults`), styled like the live workout's "Add exercise".
/// - **Your core workout** — the exercises the user has picked, followed by
///   "Save" / "Start" actions.
///
/// "Save" locks the workout: the setup fields freeze and the per-exercise delete
/// controls hide, and the button becomes "Edit" to unlock. "Start" is a
/// placeholder for now (not wired up).
struct CoreView: View {
    /// Read-only reference to the parent VM (same pattern as `ExerciseCard`).
    /// `@Observable` tracks the property reads in `body`, so the view refreshes
    /// as core exercises / setup / lock state change.
    let viewModel: LiveWorkoutViewModel

    /// Whether the "Add core exercise" picker sheet is showing.
    @State private var showAddExercise = false
    /// The running core-workout timer, if "Start" was pressed. Non-nil presents
    /// the full-screen `CoreTimerView`.
    @State private var runningTimer: CoreWorkoutTimer?

    /// Core exercises not yet added — what the picker offers.
    private var availableExercises: [String] {
        CoreExercise.defaults.filter { !viewModel.addedCoreExercises.contains($0) }
    }

    var body: some View {
        Form {
            Section("Setup") {
                setupConfigRow
                addCoreButton
            }

            Section {
                if viewModel.addedCoreExercises.isEmpty {
                    Text("No core exercises yet. Tap \u{201C}Add core exercise\u{201D} to build your core workout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.addedCoreExercises.enumerated()), id: \.element) { index, name in
                        coreExercise(name, number: index + 1)
                    }
                }
            } header: {
                // Title on the leading edge; the setup-derived duration estimate
                // on the trailing edge (hidden until a positive set count is set).
                HStack {
                    Text("Your core workout")
                    Spacer()
                    if let estimate = viewModel.coreEstimatedSeconds {
                        Text(formatEstimate(estimate))
                    }
                }
            }
            // Keep the header's casing as written (so the estimate reads "6:00
            // min", not "6:00 MIN").
            .textCase(nil)
            // Tighten (but don't collapse) the gap between the list and the
            // Save/Start buttons.
            .listSectionSpacing(16)

            actionButtons

            if let actionError = viewModel.actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Core")
        .navigationBarTitleDisplayMode(.inline)
        // Same swipe-up sheet style as the live workout's "Add exercise": a
        // default full-height sheet hosting a NavigationStack picker.
        .sheet(isPresented: $showAddExercise) {
            CoreExercisePickerSheet(available: availableExercises) { name in
                viewModel.addCoreExercise(name)
            }
        }
        // Running core workout — full-screen interval timer.
        .fullScreenCover(item: $runningTimer) { timer in
            CoreTimerView(timer: timer) { runningTimer = nil }
        }
    }

    // MARK: - Setup

    /// Time / Rest inputs (both in seconds), styled with the shared boxed field.
    /// There's no Sets field — the number of sets is the count of added
    /// exercises. Frozen once the workout is locked.
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

    /// Binding to a mutable String property on the (observable) view model —
    /// lets the setup TextFields write straight through without a local mirror.
    private func bindingFor(_ keyPath: ReferenceWritableKeyPath<LiveWorkoutViewModel, String>) -> Binding<String> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    /// "Add core exercise" — styled like `LiveWorkoutView.actionRow` (leading
    /// plus icon + accent label). Disabled once every core exercise is added or
    /// the workout is locked.
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
    private func coreExercise(_ name: String, number: Int) -> some View {
        HStack(spacing: 12) {
            numberBadge(number)
            Text(name)
                .font(.headline)
            Spacer()
            if !viewModel.isCoreWorkoutLocked {
                Button(role: .destructive) {
                    Task { await viewModel.removeCoreExercise(name) }
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
    /// workout's "Complete Workout" CTA (edge-to-edge, no card surface). While
    /// Start is disabled, a muted hint sits underneath it. The buttons live in one
    /// list row (VStack) so the row insets/background are cleared once and the two
    /// keep a consistent vertical gap.
    private var actionButtons: some View {
        Section {
            VStack(spacing: 12) {
                saveEditButton
                startButton
                if !canStart {
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

    /// "Save" locks the workout (freezes setup, hides deletes) and flips to
    /// "Edit" to unlock.
    private var saveEditButton: some View {
        Button {
            viewModel.isCoreWorkoutLocked.toggle()
        } label: {
            Text(viewModel.isCoreWorkoutLocked ? "Edit" : "Save")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
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
        .disabled(!canStart)
    }

    /// A workout is runnable when there's at least one exercise (each is a set)
    /// and a positive work time.
    private var canStart: Bool {
        !viewModel.addedCoreExercises.isEmpty && setupSeconds.time > 0
    }

    private func startCoreWorkout() {
        let timer = CoreWorkoutTimer(
            sets: viewModel.addedCoreExercises.count,
            workSeconds: setupSeconds.time,
            restSeconds: setupSeconds.rest,
            exercises: viewModel.addedCoreExercises
        )
        guard !timer.phases.isEmpty else { return }
        runningTimer = timer
    }

    /// Parses the Time / Rest fields into seconds (blank → 0).
    private var setupSeconds: (time: Int, rest: Int) {
        func value(_ text: String) -> Int { Int(text.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return (value(viewModel.coreSetupTimeText), value(viewModel.coreSetupRestText))
    }

    // MARK: - Helpers

    /// Formats a duration in seconds as "m:ss min" (e.g. 360 → "6:00 min").
    private func formatEstimate(_ seconds: Int) -> String {
        String(format: "%d:%02d min", seconds / 60, seconds % 60)
    }
}

// MARK: - Core exercise picker

/// Swipe-up picker for adding a core exercise, mirroring `ExerciseSearchSheet`'s
/// structure (NavigationStack + inline title + Cancel) but backed by the fixed
/// `CoreExercise.defaults` list instead of a server search.
private struct CoreExercisePickerSheet: View {
    /// Core exercises available to add (defaults minus already-added).
    let available: [String]
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Pick a core exercise to log.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(available, id: \.self) { name in
                    Button {
                        onPick(name)
                        dismiss()
                    } label: {
                        Text(name).foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
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
