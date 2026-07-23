import SwiftUI

/// "Strength on the Go" browse screen: the standalone-workout catalog grouped
/// by category. Pushed from the Home tab's card, so it lives inside Home's
/// NavigationStack. Rows push the workout detail; the toolbar clock pushes the
/// completed-session history.
struct StandaloneWorkoutListView: View {
    @State private var viewModel: StandaloneWorkoutListViewModel
    @Environment(LiveWorkoutPresentation.self) private var liveWorkout
    private let repository: StandaloneWorkoutRepository
    private let workoutRepository: WorkoutRepository
    private let sessionManager: SessionManager

    init(
        viewModel: StandaloneWorkoutListViewModel,
        repository: StandaloneWorkoutRepository,
        workoutRepository: WorkoutRepository,
        sessionManager: SessionManager
    ) {
        _viewModel = State(initialValue: viewModel)
        self.repository = repository
        self.workoutRepository = workoutRepository
        self.sessionManager = sessionManager
    }

    var body: some View {
        content
            .navigationTitle("Strength on the Go")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        StandaloneHistoryView(viewModel: StandaloneHistoryViewModel(
                            repository: repository,
                            sessionManager: sessionManager
                        ), repository: repository)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Workout history")
                }
            }
            .task { if viewModel.workouts.isEmpty { await viewModel.load() } }
            .refreshable { await viewModel.load() }
            // Re-check the "In progress" badges when the live cover dismisses
            // (the session may have been completed or abandoned).
            .onChange(of: liveWorkout.isPresented) { wasPresented, isPresented in
                if wasPresented && !isPresented {
                    Task { await viewModel.refreshActiveSessions() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.workouts.isEmpty {
            // Every branch must render a real view: `.task` hangs off `content`,
            // and appear modifiers never fire on an EmptyView — a blank branch
            // here would keep the initial load() from ever running.
            if !viewModel.hasLoadedOnce || viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError = viewModel.loadError {
                ContentUnavailableView(
                    "Couldn't load workouts",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError.localizedDescription)
                )
            } else {
                ContentUnavailableView(
                    "No workouts available",
                    systemImage: "figure.strengthtraining.functional",
                    description: Text("Check back soon for on-the-go workouts.")
                )
            }
        } else {
            List {
                Section {
                    Text("Quick 30–45 minute workouts you can do any time. They don't affect your program.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                ForEach(viewModel.groupedByCategory, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.workouts) { workout in
                            NavigationLink {
                                StandaloneWorkoutDetailView(
                                    viewModel: StandaloneWorkoutDetailViewModel(
                                        workoutId: workout.id,
                                        repository: repository,
                                        workoutRepository: workoutRepository,
                                        sessionManager: sessionManager
                                    )
                                )
                            } label: {
                                StandaloneWorkoutRow(
                                    workout: workout,
                                    isInProgress: viewModel.activeSession(forWorkoutId: workout.id) != nil
                                )
                            }
                        }
                    }
                }

                if let loadError = viewModel.loadError {
                    Text(loadError.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

/// One catalog row: name (with category/order fallback), description preview,
/// group count, and an "In progress" badge when a session is active.
private struct StandaloneWorkoutRow: View {
    let workout: StandaloneWorkoutSummaryDTO
    let isInProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(workout.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if isInProgress {
                    Text("In progress")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            if let description = workout.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("\(workout.count.groups) group\(workout.count.groups == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
