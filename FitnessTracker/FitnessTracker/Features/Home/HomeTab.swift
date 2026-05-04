import SwiftUI

struct HomeTab: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        let homeRepo = HomeRepository(apiClient: apiClient)
        let workoutRepo = WorkoutRepository(apiClient: apiClient)
        let viewModel = HomeViewModel(repository: homeRepo, sessionManager: sessionManager)
        NavigationStack {
            HomeView(
                viewModel: viewModel,
                homeRepository: homeRepo,
                workoutRepository: workoutRepo
            )
            .settingsToolbarItem()
        }
    }
}
