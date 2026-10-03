import Foundation

/// GET /api/auth/me (and the PATCH response) — the authenticated user's own
/// profile and settings. The only shape that carries the caller's email.
///
/// The social settings are optional so an older payload (or a test fixture)
/// without them still decodes; the server always sends them now.
nonisolated struct UserProfile: Codable, Sendable, Equatable {
    let id: String
    let email: String
    let name: String?
    let avatarUrl: String?
    var profileVisibility: ProfileVisibility? = nil
    /// Without a leading `@`; show it as `@username`.
    var username: String? = nil
    var bio: String? = nil
    /// Whether people who can see my posts also see my active program's name.
    var showActiveProgram: Bool? = nil
    /// Whether people who can see my posts also see my completed-workout count.
    var showWorkoutCount: Bool? = nil
}
