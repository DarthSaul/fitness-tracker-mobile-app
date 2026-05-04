import Foundation

/// Wire format for `GET /api/feedback`. The server augments the Prisma row
/// with a Supabase `screenshotUrl` for clients to render and a `user.name`
/// for display.
nonisolated struct FeedbackDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let content: String
    let screenshotPath: String?
    let screenshotUrl: String?
    let addressed: Bool
    let createdAt: Date
    let user: UserRef

    nonisolated struct UserRef: Codable, Sendable, Equatable {
        let name: String?
    }
}

/// PATCH /api/feedback/[id] — currently only flips `addressed`.
nonisolated struct UpdateFeedbackBody: Encodable, Sendable {
    let addressed: Bool
}
