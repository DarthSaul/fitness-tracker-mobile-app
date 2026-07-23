import SwiftUI

/// Completed standalone sessions, newest first, with infinite scroll. Pushed
/// from the browse screen's toolbar clock, inside the Home NavigationStack.
struct StandaloneHistoryView: View {
    @State private var viewModel: StandaloneHistoryViewModel
    @Environment(SessionManager.self) private var sessionManager
    private let repository: StandaloneWorkoutRepository

    init(viewModel: StandaloneHistoryViewModel, repository: StandaloneWorkoutRepository) {
        _viewModel = State(initialValue: viewModel)
        self.repository = repository
    }

    var body: some View {
        content
            .navigationTitle("On the Go History")
            .navigationBarTitleDisplayMode(.inline)
            .task { if viewModel.sessions.isEmpty { await viewModel.load() } }
            .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.sessions.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.sessions.isEmpty {
            // Surface the load error rather than falling through to a generic
            // empty state — a fetch failure shouldn't look like "no workouts".
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
                    description: Text("Completed on-the-go workouts will show up here.")
                )
            }
        } else {
            List {
                ForEach(viewModel.sessions) { session in
                    NavigationLink {
                        StandaloneSessionDetailView(
                            viewModel: StandaloneSessionDetailViewModel(
                                sessionId: session.id,
                                repository: repository,
                                sessionManager: sessionManager
                            )
                        )
                    } label: {
                        StandaloneHistoryRow(session: session)
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
        }
    }
}

/// One history row: completion date headline, workout name subtitle, set count.
private struct StandaloneHistoryRow: View {
    let session: StandaloneSessionListItemDTO

    /// Cached so repeated row renders don't allocate a new formatter per row.
    private static let headlineDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.headlineDateFormatter.string(from: session.completedAt ?? session.startedAt))
                    .font(.subheadline.weight(.semibold))
                Text(session.standaloneWorkout.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(session.count.completedSets) set\(session.count.completedSets == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
