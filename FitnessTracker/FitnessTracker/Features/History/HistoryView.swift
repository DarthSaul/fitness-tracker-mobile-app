import SwiftUI

/// Full-list workout history. Hosted by HistoryTab inside a NavigationStack.
/// Program and standalone completions interleave chronologically (unified
/// GET /api/history); rows push the matching detail view for their type.
struct HistoryView: View {
    @State private var viewModel: HistoryViewModel
    @Environment(SessionManager.self) private var sessionManager
    private let workoutRepository: WorkoutRepository
    private let standaloneRepository: StandaloneWorkoutRepository

    init(
        viewModel: HistoryViewModel,
        workoutRepository: WorkoutRepository,
        standaloneRepository: StandaloneWorkoutRepository
    ) {
        _viewModel = State(initialValue: viewModel)
        self.workoutRepository = workoutRepository
        self.standaloneRepository = standaloneRepository
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                ScreenTitleHeader(title: "History", emoji: "🕒")
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { if viewModel.sessions.isEmpty { await viewModel.load() } }
            .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.sessions.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.sessions.isEmpty {
            // Surface the load error rather than falling through to a generic
            // "no workouts yet" empty state — otherwise a fetch failure looks
            // identical to a brand-new account with no history.
            if let loadError = viewModel.loadError {
                ContentUnavailableView(
                    "Couldn't load history",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError.localizedDescription)
                )
            } else {
                ContentUnavailableView(
                    "No workouts yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed workouts will show up here.")
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Matches the "Strength progress" subtitle treatment on the
                // Analytics tab: subheadline/secondary, 12pt below the title
                // (same as Analytics' scroll content top padding).
                Text("Completed workouts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 12)

                List {
                ForEach(viewModel.sessions) { entry in
                    NavigationLink {
                        detailDestination(for: entry)
                    } label: {
                        HistoryRow(entry: entry)
                    }
                    .onAppear {
                        if entry.id == viewModel.sessions.last?.id, !viewModel.isLoadingMore {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                if let loadError = viewModel.loadError {
                    Text(loadError.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                }
                // Pull the list up under the subtitle — matches the
                // subtitle → content spacing used on the Analytics tab (16pt).
                .contentMargins(.top, 16, for: .scrollContent)
            }
        }
    }

    @ViewBuilder
    private func detailDestination(for entry: HistoryEntryDTO) -> some View {
        switch entry {
        case .program(let session):
            WorkoutDetailView(viewModel: WorkoutDetailViewModel(
                workoutId: session.id,
                repository: workoutRepository
            ))
        case .standalone(let session):
            StandaloneSessionDetailView(viewModel: StandaloneSessionDetailViewModel(
                sessionId: session.id,
                repository: standaloneRepository,
                sessionManager: sessionManager
            ))
        }
    }
}
