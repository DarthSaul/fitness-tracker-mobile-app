import SwiftUI

/// Today-view card with three states keyed off HomeViewModel:
///   1. Active workout exists  → "Resume workout" with X/Y sets progress.
///   2. Active program but no active workout → the Next Up card: program and
///      position, exercise preview, program progress bar, then a "Start
///      workout" button with a square Preview button beside it.
///   3. No active program → empty state pointing at the Programs tab.
struct HomeTodayCard: View {
    let viewModel: HomeViewModel

    var body: some View {
        if let active = viewModel.activeWorkout {
            ResumeCard(active: active)
        } else if let program = viewModel.activeProgram {
            StartNextCard(viewModel: viewModel, program: program)
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
    /// Unwrapped by the parent's `if let`. Passed as a value rather than
    /// re-read from `viewModel.activeProgram` here: when a reload clears the
    /// active program, SwiftUI can re-evaluate this body in the same
    /// transaction before HomeTodayCard swaps it out, so a force-unwrap
    /// inside this body crashes (DR-DUMBBELL-IOS-6).
    let program: ActiveUserProgramDTO
    @Environment(LiveWorkoutPresentation.self) private var liveWorkout
    @State private var showPreview = false
    /// "One active workout at a time" prompt — shown when Start is tapped
    /// while a standalone session is still in progress.
    @State private var showStandaloneConflict = false

    var body: some View {
        // Card is no longer wrapped in one big Button — Preview and Start are
        // both real interactive controls inside a non-tappable container so
        // they don't collide with each other or with NavigationLink/Sheet
        // semantics around the card.
        HomeCardChrome(minHeight: nil) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Next up · \(program.program.name)")
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(viewModel.completedDays)/\(viewModel.totalDays)")
                            .monospacedDigit()
                            .accessibilityLabel("\(viewModel.completedDays) of \(viewModel.totalDays) workouts done")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                    Text("Week \(program.currentWeek) · Day \(program.currentDay)")
                        .font(.system(size: 21, weight: .bold))
                }

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

                ProgramProgressBar(fraction: Double(viewModel.progressPercent) / 100)
                    .padding(.top, 4)

                HStack(spacing: 8) {
                    Button {
                        if viewModel.blockingStandaloneSession != nil {
                            showStandaloneConflict = true
                        } else {
                            Task { await startAndPresent() }
                        }
                    } label: {
                        Text(viewModel.isStartingWorkout ? "Starting…" : "Start workout")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isStartingWorkout)
                    .opacity(viewModel.isStartingWorkout ? 0.6 : 1)

                    Button {
                        showPreview = true
                    } label: {
                        Image(systemName: "eye")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Color(.systemGray4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview workout")
                }
                .padding(.top, 6)

                if let startConflictError = viewModel.startConflictError {
                    Text(startConflictError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $showPreview) {
            WorkoutPreviewSheet(day: viewModel.nextWorkoutDay)
        }
        .alert("Workout in progress", isPresented: $showStandaloneConflict) {
            Button("Complete it") {
                Task {
                    if await viewModel.resolveStandaloneSessions(discard: false) {
                        await startAndPresent()
                    }
                }
            }
            Button("Discard it", role: .destructive) {
                Task {
                    if await viewModel.resolveStandaloneSessions(discard: true) {
                        await startAndPresent()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You're in the middle of \(viewModel.blockingStandaloneSession?.standaloneWorkout.displayName ?? "a standalone workout"). Complete it or discard it to start your program workout.")
        }
    }

    private func startAndPresent() async {
        if await viewModel.startNextWorkout() != nil {
            liveWorkout.present()
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

/// Card with the brand-gradient accent bar down its leading edge.
private struct HomeCardChrome<Content: View>: View {
    /// The Next Up card sizes to its content; the other states keep a
    /// minimum height so the card doesn't jump between them.
    var minHeight: CGFloat? = 180
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [SocialStyle.brandPink, SocialStyle.brandRose],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 5)

            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// 4pt program progress bar (track gray, fill blue).
private struct ProgramProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray4))
                Capsule()
                    .fill(Color.blue)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
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
