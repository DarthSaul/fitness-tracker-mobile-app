import SwiftUI

/// Past-date view: a preview of the workout the user completed on the selected
/// date. Tapping pushes the read-only `WorkoutDetailView`. Mirrors the card
/// chrome of `HomeScheduledCard` (gradient bar + rounded surface), using a
/// green gradient to signal "done".
struct HomeCompletedCard: View {
    let viewModel: HomeViewModel
    let session: ActiveProgramSessionDTO
    let workoutRepository: WorkoutRepository

    var body: some View {
        NavigationLink {
            WorkoutDetailView(viewModel: WorkoutDetailViewModel(
                workoutId: session.id,
                repository: workoutRepository
            ))
        } label: {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.green, .mint],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text("Week \(session.weekNumber), Day \(session.dayNumber)")
                            .font(.headline)
                        if let name = viewModel.dayName(forWeek: session.weekNumber, day: session.dayNumber) {
                            Text("— \(name)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("^[\(session.count.completedSets) set](inflect: true) logged")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 16)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// Past-date view when no workout was completed that day. Scheduling is
/// future-only, so we show a neutral placeholder rather than the Schedule CTA.
struct HomeNoWorkoutCard: View {
    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.gray, .gray.opacity(0.5)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text("No workout")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("No workout on this day")
                    .font(.headline)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
