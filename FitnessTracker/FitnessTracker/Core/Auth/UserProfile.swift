import Foundation

/// GET /api/auth/me — basic identity info for the authenticated user.
nonisolated struct UserProfile: Codable, Sendable, Equatable {
    let id: String
    let email: String
    let name: String?
    let avatarUrl: String?
}
