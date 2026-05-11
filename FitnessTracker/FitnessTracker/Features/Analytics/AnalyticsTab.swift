import SwiftUI

/// Analytics tab — instantiates the repository and view model and provides
/// the NavigationStack the analytics view renders inside.
struct AnalyticsTab: View {
    @Environment(APIClient.self) private var apiClient

    var body: some View {
        let repo = AnalyticsRepository(apiClient: apiClient)
        let viewModel = AnalyticsViewModel(repository: repo)
        NavigationStack {
            AnalyticsView(viewModel: viewModel)
        }
    }
}
