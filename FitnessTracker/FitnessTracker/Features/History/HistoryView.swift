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
            .navigationTitle("History")
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
            ContentUnavailableView(
                "No workouts yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("Completed workouts will show up here.")
            )
        } else {
            List {
                ForEach(viewModel.sessions) { session in
                    NavigationLink(value: session.id) {
                        HistoryRow(session: session)
                    }
                    .onAppear {
                        if session.id == viewModel.sessions.last?.id {
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
        }
    }
}
