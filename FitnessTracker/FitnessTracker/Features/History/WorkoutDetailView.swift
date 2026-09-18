import SwiftUI

/// Summary of a completed workout. Reuses the active-workout endpoint
/// (`GET /api/workouts/:id`) which returns the same `{ session, day }` shape
/// for completed sessions. The toolbar's edit icon pushes the same
/// ProgramDayEditView that Manage Program uses — the server lets any owned
/// session be edited in isolation, with or without an active program.
struct WorkoutDetailView: View {
    @State private var viewModel: WorkoutDetailViewModel
    /// Fired after an edit lands so the presenting list can refresh (an
    /// edited date re-sorts the row).
    private let onChange: () -> Void

    init(viewModel: WorkoutDetailViewModel, onChange: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onChange = onChange
    }

    var body: some View {
        content
            .navigationTitle(headerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editToolbar }
            .task { await viewModel.load() }
    }

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        if let workout = viewModel.workout {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ProgramDayEditView(
                        weekNumber: workout.session.weekNumber,
                        day: workout.day,
                        existingSessionId: workout.session.id,
                        repository: viewModel.repository,
                        onChange: {
                            Task { await viewModel.load() }
                            onChange()
                        }
                    )
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit workout")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.workout == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let workout = viewModel.workout {
            workoutForm(for: workout)
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

    private var headerTitle: String {
        guard let s = viewModel.workout?.session else { return "Workout" }
        return "Week \(s.weekNumber) · Day \(s.dayNumber)"
    }

    @ViewBuilder
    private func workoutForm(for workout: ActiveWorkoutResponseDTO) -> some View {
        Form {
            if let completedAt = workout.session.completedAt {
                Section {
                    LabeledContent("Completed", value: formattedDate(completedAt))
                }
            }

            if let warmUp = workout.day.warmUp, !warmUp.isEmpty {
                Section("Warm-up") { Text(warmUp) }
            }

            ForEach(workout.day.exerciseGroups, id: \.id) { group in
                Section {
                    ForEach(group.exercises, id: \.id) { exercise in
                        CompletedExerciseRow(
                            exercise: exercise,
                            completedSets: workout.session.completedSets
                        )
                    }
                } header: {
                    Text(group.type == .superset ? "Superset" : "Standard")
                }
            }

            adhocSection(for: workout)

            if let notes = workout.session.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
    }

    @ViewBuilder
    private func adhocSection(for workout: ActiveWorkoutResponseDTO) -> some View {
        let adhocSets = workout.session.completedSets.filter { $0.adhocExerciseName != nil }
        if !adhocSets.isEmpty {
            Section("Ad-hoc") {
                ForEach(adhocSets) { set in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(set.adhocExerciseName ?? "Exercise")
                            .font(.subheadline)
                        Text(formatSet(reps: set.reps, weight: set.weight, rpe: set.rpe))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: date)
    }
}

/// One template exercise rendered with each set's logged values inline. Pulls
/// the per-set match from `completedSets` via `exerciseSetId`. Extra (non-template)
/// sets for the same exercise are appended underneath as numbered rows.
private struct CompletedExerciseRow: View {
    let exercise: ProgramExerciseDTO
    let completedSets: [CompletedSetDTO]

    private var completedByTemplateId: [String: CompletedSetDTO] {
        var result: [String: CompletedSetDTO] = [:]
        for set in completedSets {
            if let id = set.exerciseSetId {
                result[id] = set
            }
        }
        return result
    }

    private var extras: [CompletedSetDTO] {
        completedSets
            .filter { $0.programExerciseId == exercise.id && $0.exerciseSetId == nil }
            .sorted { $0.completedAt < $1.completedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.exercise.name)
                .font(.headline)
            ForEach(exercise.sets, id: \.id) { templateSet in
                HStack {
                    Text("Set \(templateSet.setNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let logged = completedByTemplateId[templateSet.id] {
                        Text(formatSet(reps: logged.reps, weight: logged.weight, rpe: logged.rpe))
                            .font(.subheadline.monospacedDigit())
                    } else {
                        Text("Skipped")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            ForEach(Array(extras.enumerated()), id: \.element.id) { offset, extra in
                HStack {
                    Text("Extra \(offset + 1)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatSet(reps: extra.reps, weight: extra.weight, rpe: extra.rpe))
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
        .padding(.vertical, 4)
    }
}
