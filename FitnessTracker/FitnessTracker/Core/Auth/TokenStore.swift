import Foundation

/// In-memory access-token holder, isolated as an actor so reads and writes
/// from APIClient (called from arbitrary executors), SessionManager (main
/// actor), and TokenRefresher (its own actor) can't race on the same state.
actor TokenStore {
    private var accessToken: String?

    func getAccessToken() -> String? {
        accessToken
    }

    func set(access token: String) {
        accessToken = token
    }

    func clear() {
        accessToken = nil
    }
}
