import SwiftUI

/// Read-only view of a completed standalone session, mirroring the program
/// history's WorkoutDetailView: template exercises with each set's logged
/// values inline, plus an Ad-hoc section. (The program history detail offers
/// no corrections, so this one doesn't either.)
struct StandaloneSessionDetailView: View {
    @State private var viewModel: StandaloneSessionDetailViewModel

    init(viewModel: StandaloneSessionDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle(viewModel.detail?.workout.displayName ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.detail == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = viewModel.detail {
            sessionForm(for: detail)
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

    @ViewBuilder
    private func sessionForm(for detail: StandaloneSessionDetailResponseDTO) -> some View {
        Form {
            if let completedAt = detail.session.completedAt {
                Section {
                    LabeledContent("Completed", value: formattedDate(completedAt))
                }
            }

            ForEach(detail.workout.groups, id: \.id) { group in
                Section {
                    ForEach(group.exercises, id: \.id) { exercise in
                        CompletedStandaloneExerciseRow(
                            exercise: exercise,
                            completedSets: detail.session.completedSets
                        )
                    }
                } header: {
                    Text(groupHeader(for: group))
                }
            }

            adhocSection(for: detail)

            if let notes = detail.session.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
    }

    /// Group label wins when present (e.g. "Cardio"); otherwise the type.
    private func groupHeader(for group: StandaloneWorkoutGroupDTO) -> String {
        if let label = group.label, !label.isEmpty { return label }
        return group.type == .superset ? "Superset" : "Standard"
    }

    @ViewBuilder
    private func adhocSection(for detail: StandaloneSessionDetailResponseDTO) -> some View {
        // Only sets whose name doesn't match a template exercise — same-named
        // ad-hoc sets already render as extra rows inside the exercise rows.
        let templateNames = Set(detail.workout.groups.flatMap { $0.exercises.map(\.exercise.name) })
        let adhocSets = detail.session.completedSets.filter {
            guard let name = $0.adhocExerciseName else { return false }
            return !templateNames.contains(name)
        }
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

/// One template exercise rendered with each set's logged values inline,
/// matched via `standaloneWorkoutSetId`. Ad-hoc sets logged under this
/// exercise's name are appended as "Extra" rows underneath.
private struct CompletedStandaloneExerciseRow: View {
    let exercise: StandaloneWorkoutExerciseDTO
    let completedSets: [StandaloneCompletedSetDTO]

    private var completedByTemplateId: [String: StandaloneCompletedSetDTO] {
        var result: [String: StandaloneCompletedSetDTO] = [:]
        for set in completedSets {
            if let id = set.standaloneWorkoutSetId {
                result[id] = set
            }
        }
        return result
    }

    private var extras: [StandaloneCompletedSetDTO] {
        completedSets
            .filter { $0.adhocExerciseName == exercise.exercise.name }
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
