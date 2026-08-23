import SwiftUI

/// Past-date view: a preview of a workout the user completed on the selected
/// date — either flavor of unified-history row. Tapping pushes the read-only
/// detail view for the entry's type. Mirrors the card chrome of
/// `HomeScheduledCard` (gradient bar + rounded surface), using a green
/// gradient to signal "done".
struct HomeCompletedCard: View {
    let viewModel: HomeViewModel
    let entry: HistoryEntryDTO
    let workoutRepository: WorkoutRepository
    let standaloneRepository: StandaloneWorkoutRepository
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        NavigationLink {
            destination
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
                    Text(headline)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("^[\(entry.completedSets) set](inflect: true) logged")
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

    private var headline: String {
        switch entry {
        case .program(let session):
            return session.programName
        case .standalone(let session):
            return session.standaloneWorkout.displayName
        }
    }

    private var subtitle: String {
        switch entry {
        case .program(let session):
            var text = "Week \(session.weekNumber), Day \(session.dayNumber)"
            // dayName reads the ACTIVE program's tree, so the lookup is only
            // meaningful for sessions belonging to that program.
            if session.userProgramId == viewModel.activeProgram?.id,
               let name = viewModel.dayName(forWeek: session.weekNumber, day: session.dayNumber) {
                text += " — \(name)"
            }
            return text
        case .standalone(let session):
            return session.standaloneWorkout.category
        }
    }

    @ViewBuilder
    private var destination: some View {
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
