import SwiftUI

struct HomeTab: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        let repo = HomeRepository(apiClient: apiClient)
        let viewModel = HomeViewModel(repository: repo, sessionManager: sessionManager)
        NavigationStack {
            HomeView(viewModel: viewModel)
                .settingsToolbarItem()
        }
    }
}
