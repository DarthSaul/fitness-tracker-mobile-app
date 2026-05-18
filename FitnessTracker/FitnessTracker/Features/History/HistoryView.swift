import SwiftUI

/// Full-list workout history. Hosted by HistoryTab inside a NavigationStack.
struct HistoryView: View {
    @State private var viewModel: HistoryViewModel
    private let workoutRepository: WorkoutRepository

    init(viewModel: HistoryViewModel, workoutRepository: WorkoutRepository) {
        _viewModel = State(initialValue: viewModel)
        self.workoutRepository = workoutRepository
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                ScreenTitleHeader(title: "History", emoji: "🕒")
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { if viewModel.sessions.isEmpty { await viewModel.load() } }
            .refreshable { await viewModel.load() }
            .navigationDestination(for: String.self) { workoutId in
                WorkoutDetailView(viewModel: WorkoutDetailViewModel(
                    workoutId: workoutId,
                    repository: workoutRepository
                ))
            }
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
                ForEach(viewModel.sessions) { session in
                    NavigationLink(value: session.id) {
                        HistoryRow(session: session)
                    }
                    .onAppear {
                        if session.id == viewModel.sessions.last?.id, !viewModel.isLoadingMore {
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
}
