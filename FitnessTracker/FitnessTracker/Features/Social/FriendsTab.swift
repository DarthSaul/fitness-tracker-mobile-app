import SwiftUI

/// Friends tab — the following feed with a post composer. Instantiates the
/// repository and view model and provides the NavigationStack.
struct FriendsTab: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        let viewModel = FeedViewModel(
            repository: FeedRepository(apiClient: apiClient),
            sessionManager: sessionManager
        )
        NavigationStack {
            FriendsView(viewModel: viewModel)
        }
    }
}
