import SwiftUI

/// Home-page entry card for standalone on-demand workouts. Pushes the
/// "Strength on the Go" browse screen within the Home tab's NavigationStack.
/// Chrome matches the other Home cards (rounded 14, secondary background,
/// trailing accent pill) with the today-card's purple→pink gradient as the
/// icon accent.
struct StrengthOnTheGoCard: View {
    let standaloneRepository: StandaloneWorkoutRepository
    let workoutRepository: WorkoutRepository
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        NavigationLink {
            StandaloneWorkoutListView(
                viewModel: StandaloneWorkoutListViewModel(
                    repository: standaloneRepository,
                    sessionManager: sessionManager
                ),
                repository: standaloneRepository,
                workoutRepository: workoutRepository,
                sessionManager: sessionManager
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.functional")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Strength on the Go")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Quick 30–45 minute workouts, any time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Browse")
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
