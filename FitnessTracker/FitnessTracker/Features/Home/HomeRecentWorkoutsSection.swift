import SwiftUI

/// Home's History section: the user's five most recent completed workouts,
/// as the same rows Progress → History shows. "See all" opens that list.
struct HomeRecentWorkoutsSection: View {
    static let limit = 5

    let entries: [HistoryEntryDTO]
    /// Whether history has ever loaded; an empty list before that is a
    /// failed fetch, not an account with no workouts.
    let hasLoaded: Bool
    let isLoading: Bool
    let onRetry: () -> Void
    let workoutRepository: WorkoutRepository
    let standaloneRepository: StandaloneWorkoutRepository
    /// Called after a program workout is edited from its detail view.
    let onChange: () -> Void
    @Environment(TabSelection.self) private var tabSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeaderText("History", uppercased: false)
                Spacer()
                Button("See all") {
                    tabSelection.progressSection = .history
                    tabSelection.select(.progress)
                }
                .font(.system(size: 15))
            }
            .padding(.horizontal, 2)

            card
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var card: some View {
        if entries.isEmpty && !hasLoaded {
            SocialRow(showsSeparator: false) {
                Text("Couldn't load your workouts.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Button("Retry", action: onRetry)
                        .font(.system(size: 15))
                }
            }
            .background(SocialStyle.card, in: cardShape)
        } else if entries.isEmpty {
            SocialRow(showsSeparator: false) {
                Text("Completed workouts will show up here.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .background(SocialStyle.card, in: cardShape)
        } else {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    NavigationLink {
                        HistoryEntryDestination(
                            entry: entry,
                            workoutRepository: workoutRepository,
                            standaloneRepository: standaloneRepository,
                            onChange: onChange
                        )
                    } label: {
                        SocialRow(showsSeparator: entry.id != entries.last?.id) {
                            HistoryRow(entry: entry)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(SocialStyle.card, in: cardShape)
            .clipShape(cardShape)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous)
    }
}
