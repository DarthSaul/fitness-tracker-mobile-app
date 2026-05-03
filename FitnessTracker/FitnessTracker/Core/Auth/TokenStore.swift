import Foundation
import Observation

@Observable
final class TokenStore {
    // MARK: - State (access token lives in memory only)
    private(set) var accessToken: String?

    // MARK: - Mutations
    func set(access token: String) {
        accessToken = token
    }

    func clear() {
        accessToken = nil
    }
}
