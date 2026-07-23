import SwiftUI

/// Recent-history section on the home page. Renders up to 5 rows from
/// `HomeViewModel.recentHistory` — program and standalone completions
/// interleaved — each a NavigationLink into the read-only detail view for its
/// type, plus a "View all history" button that flips the tab.
struct HomeRecentHistorySection: View {
    let recentHistory: [HistoryEntryDTO]
    let workoutRepository: WorkoutRepository
    let standaloneRepository: StandaloneWorkoutRepository
    /// Suppresses the "completed workouts will show up here" hint until the
    /// initial fetch has completed — avoids flashing empty-state copy while
    /// recent history is still loading on a fresh sign-in.
    let hasLoadedOnce: Bool
    @Environment(TabSelection.self) private var tabSelection
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HISTORY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            if recentHistory.isEmpty {
                if hasLoadedOnce {
                    Text("Completed workouts will show up here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentHistory.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink {
                            detailDestination(for: entry)
                        } label: {
                            HStack {
                                HistoryRow(entry: entry)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if index < recentHistory.count - 1 {
                            Divider().padding(.leading)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

                Button {
                    tabSelection.select(.history)
                } label: {
                    HStack(spacing: 4) {
                        Text("View all history")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal)
                .padding(.top, 4)
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
