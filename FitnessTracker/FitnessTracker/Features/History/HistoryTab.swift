import SwiftUI

struct HistoryTab: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        let historyRepo = HistoryRepository(apiClient: apiClient)
        let workoutRepo = WorkoutRepository(apiClient: apiClient)
        let standaloneRepo = StandaloneWorkoutRepository(apiClient: apiClient)
        let viewModel = HistoryViewModel(repository: historyRepo, sessionManager: sessionManager)
        NavigationStack {
            HistoryView(
                viewModel: viewModel,
                workoutRepository: workoutRepo,
                standaloneRepository: standaloneRepo
            )
        }
    }
}
