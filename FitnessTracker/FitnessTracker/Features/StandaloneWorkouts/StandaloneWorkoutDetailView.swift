import SwiftUI

/// Read-only template preview for one standalone workout — groups → exercises
/// → sets — with a Start/Resume CTA pinned to the bottom. Starting hands off
/// to the shared live-workout cover via LiveWorkoutPresentation.
struct StandaloneWorkoutDetailView: View {
    @State private var viewModel: StandaloneWorkoutDetailViewModel
    @Environment(LiveWorkoutPresentation.self) private var liveWorkout

    init(viewModel: StandaloneWorkoutDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    /// Alert presentation derived straight from the VM's blocker so a repeat
    /// block (e.g. after a failed resolve) re-presents reliably. Dismissal
    /// clears the blocker; the action buttons capture it first.
    private var blockerAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.blocker != nil },
            set: { if !$0 { viewModel.blocker = nil } }
        )
    }

    var body: some View {
        content
            .navigationTitle(viewModel.workout?.displayName ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if viewModel.workout != nil {
                    startButton
                }
            }
            .task { await viewModel.load() }
            // The CTA flips between Start and Resume based on the active
            // session — re-check when the live cover dismisses.
            .onChange(of: liveWorkout.isPresented) { wasPresented, isPresented in
                if wasPresented && !isPresented {
                    Task { await viewModel.refreshActiveSession() }
                }
            }
            .alert("Workout in progress", isPresented: blockerAlertBinding) {
                blockerDialogActions
            } message: {
                Text("You're in the middle of \(viewModel.blocker?.workoutName ?? "another workout"). Complete it or discard it to start this one.")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.workout == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let workout = viewModel.workout {
            templateList(for: workout)
        } else if let error = viewModel.loadError {
            ContentUnavailableView(
                "Couldn't load workout",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        } else {
            ContentUnavailableView("Not found", systemImage: "questionmark.folder")
        }
    }

    private func templateList(for workout: StandaloneWorkoutDetailDTO) -> some View {
        List {
            if let description = workout.description, !description.isEmpty {
                Section {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(workout.groups, id: \.id) { group in
                Section {
                    ForEach(group.exercises, id: \.id) { exercise in
                        TemplateExerciseRows(exercise: exercise)
                    }
                } header: {
                    HStack {
                        Text(groupHeader(for: group))
                        if let restSeconds = group.restSeconds, restSeconds > 0 {
                            Spacer()
                            Text("Rest \(restSeconds)s")
                        }
                    }
                }
            }

            if let actionError = viewModel.actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.footnote) }
            }
        }
    }

    /// Group label wins when present (e.g. "Cardio"); otherwise the type.
    private func groupHeader(for group: StandaloneWorkoutGroupDTO) -> String {
        if let label = group.label, !label.isEmpty { return label }
        return group.type == .superset ? "Superset" : "Standard"
    }

    // MARK: - CTA

    private var isResume: Bool { viewModel.activeSessionForThisWorkout != nil }

    private var startButton: some View {
        Button {
            Task {
                if let sessionId = await viewModel.startOrResume() {
                    liveWorkout.presentStandalone(sessionId: sessionId)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isResume ? "arrow.forward.circle.fill" : "play.circle.fill")
                Text(viewModel.isStarting ? "Starting…" : (isResume ? "Resume Workout" : "Start Workout"))
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(isResume ? .green : .accentColor)
        .disabled(viewModel.isStarting)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
    }

    @ViewBuilder
    private var blockerDialogActions: some View {
        // Capture the blocker synchronously in the button action — SwiftUI
        // clears `viewModel.blocker` (via the presentation binding) before the
        // async Task body runs.
        Button("Complete it") {
            guard let blocker = viewModel.blocker else { return }
            Task {
                if let sessionId = await viewModel.resolveBlockerAndStart(blocker, discard: false) {
                    liveWorkout.presentStandalone(sessionId: sessionId)
                }
            }
        }
        Button("Discard it", role: .destructive) {
            guard let blocker = viewModel.blocker else { return }
            Task {
                if let sessionId = await viewModel.resolveBlockerAndStart(blocker, discard: true) {
                    liveWorkout.presentStandalone(sessionId: sessionId)
                }
            }
        }
        Button("Cancel", role: .cancel) { }
    }
}

/// One template exercise with its prescribed sets, mirroring the program
/// workout-preview rows (Set N on the left, targets on the right).
private struct TemplateExerciseRows: View {
    let exercise: StandaloneWorkoutExerciseDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.exercise.name).font(.headline)
            ForEach(exercise.sets, id: \.id) { templateSet in
                HStack {
                    Text("Set \(templateSet.setNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(templateSummary(for: templateSet))
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Reps/weight/RPE summary with the display-string effort target appended
    /// when present (e.g. "10 reps · RPE 7").
    private func templateSummary(for set: StandaloneWorkoutSetDTO) -> String {
        var summary = formatSet(reps: set.reps, weight: set.weight, rpe: set.rpe)
        if let effortTarget = set.effortTarget, !effortTarget.isEmpty {
            summary = summary == "—" ? effortTarget : "\(summary) · \(effortTarget)"
        }
        return summary
    }
}
