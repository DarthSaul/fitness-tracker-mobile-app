import SwiftUI

/// Today-view card with three states keyed off HomeViewModel:
///   1. Active workout exists  → "Resume workout" with X/Y sets progress.
///   2. Active program but no active workout → "Start next workout" w/ exercise preview.
///   3. No active program → empty state pointing at the Programs tab.
///
/// PR #7 will replace the resume/start tap handlers with real navigation
/// into the live-workout view.
struct HomeTodayCard: View {
    let viewModel: HomeViewModel

    var body: some View {
        if let active = viewModel.activeWorkout {
            ResumeCard(active: active)
        } else if viewModel.hasActiveProgram {
            StartNextCard(viewModel: viewModel)
        } else if !viewModel.hasLoadedOnce {
            LoadingCard()
        } else {
            NoProgramCard()
        }
    }
}

// MARK: - Loading

private struct LoadingCard: View {
    var body: some View {
        HomeCardChrome {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading your program…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Resume

private struct ResumeCard: View {
    let active: ActiveWorkoutResponseDTO
    @Environment(LiveWorkoutPresentation.self) private var liveWorkout

    private var totalSets: Int {
        active.day.exerciseGroups.reduce(0) { sum, group in
            sum + group.exercises.reduce(0) { $0 + $1.sets.count }
        }
    }

    private var completedSets: Int {
        active.session.completedSets.count
    }

    private var progress: Double {
        guard totalSets > 0 else { return 0 }
        return min(1, max(0, Double(completedSets) / Double(totalSets)))
    }

    private var nextExerciseName: String? {
        // First exercise that still has unrecorded sets, in order.
        let recordedSetIds = Set(active.session.completedSets.compactMap(\.exerciseSetId))
        for group in active.day.exerciseGroups {
            for exercise in group.exercises {
                let unrecorded = exercise.sets.first { !recordedSetIds.contains($0.id) }
                if unrecorded != nil { return exercise.exercise.name }
            }
        }
        return nil
    }

    var body: some View {
        Button {
            liveWorkout.present()
        } label: {
            HomeCardChrome {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Week \(active.session.weekNumber) · Day \(active.session.dayNumber)")
                        .font(.headline)

                    ProgressView(value: progress)
                        .tint(.accentColor)
                        .padding(.top, 4)
                    Text("\(completedSets) / \(totalSets) sets")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let nextExerciseName {
                        Label("Next: \(nextExerciseName)", systemImage: "arrow.forward.circle")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }

                    Spacer(minLength: 0)
                    actionPill("Resume workout", systemImage: "chevron.right", tint: .green)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Start Next

private struct StartNextCard: View {
    let viewModel: HomeViewModel
    @Environment(LiveWorkoutPresentation.self) private var liveWorkout
    @State private var showPreview = false

    var body: some View {
        let program = viewModel.activeProgram!
        // Card is no longer wrapped in one big Button — Preview and Start are
        // both real interactive controls inside a non-tappable container so
        // they don't collide with each other or with NavigationLink/Sheet
        // semantics around the card.
        HomeCardChrome {
            VStack(alignment: .leading, spacing: 8) {
                Text("Next up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Week \(program.currentWeek) · Day \(program.currentDay)")
                    .font(.headline)

                if !viewModel.nextWorkoutExerciseNames.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.nextWorkoutExerciseNames.prefix(3), id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.purple)
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                        }
                        if viewModel.nextWorkoutExerciseNames.count > 3 {
                            Text("+\(viewModel.nextWorkoutExerciseNames.count - 3) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)

                Button {
                    Task {
                        if await viewModel.startNextWorkout() != nil {
                            liveWorkout.present()
                        }
                    }
                } label: {
                    actionPill(
                        viewModel.isStartingWorkout ? "Starting…" : "Start next workout",
                        systemImage: viewModel.isStartingWorkout ? "" : "chevron.right",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isStartingWorkout)

                Button {
                    showPreview = true
                } label: {
                    actionPill("Preview workout", systemImage: "eye", tint: .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showPreview) {
            WorkoutPreviewSheet(day: viewModel.nextWorkoutDay)
        }
    }
}

// MARK: - No program

private struct NoProgramCard: View {
    var body: some View {
        HomeCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                Text("No active program")
                    .font(.headline)
                Text("Activate a program from the Programs tab to start training.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared chrome
private struct HomeCardChrome<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.purple, .pink],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 8)

            content()
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Pill helper
@ViewBuilder
private func actionPill(_ title: String, systemImage: String, tint: Color) -> some View {
    HStack {
        Text(title).font(.subheadline.weight(.medium))
        Spacer()
        if !systemImage.isEmpty {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
        }
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
}
