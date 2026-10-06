import SwiftUI

/// The detail screen a unified-history row pushes: the program workout
/// detail (editable) or the standalone session detail. Shared by Progress →
/// History and Home's completed-day card and recent-workouts list.
struct HistoryEntryDestination: View {
    let entry: HistoryEntryDTO
    let workoutRepository: WorkoutRepository
    let standaloneRepository: StandaloneWorkoutRepository
    /// Called after the program workout is edited, so the list can refetch.
    var onChange: () -> Void = {}
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        switch entry {
        case .program(let session):
            WorkoutDetailView(
                viewModel: WorkoutDetailViewModel(
                    workoutId: session.id,
                    repository: workoutRepository
                ),
                onChange: onChange
            )
        case .standalone(let session):
            StandaloneSessionDetailView(viewModel: StandaloneSessionDetailViewModel(
                sessionId: session.id,
                repository: standaloneRepository,
                sessionManager: sessionManager
            ))
        }
    }
}
