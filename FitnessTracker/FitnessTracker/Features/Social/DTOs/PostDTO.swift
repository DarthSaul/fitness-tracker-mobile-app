import Foundation

/// A post, as the feed, a user's posts and the single-post routes return it.
nonisolated struct PostDTO: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let author: PublicUserDTO
    /// 0–2,000 characters; empty only on a photo or workout-share post.
    let body: String
    /// Kept raw: it's the paging cursor.
    let createdAt: WireTimestamp
    /// Non-nil → show "Edited".
    let editedAt: Date?
    let isMine: Bool
    /// Display order; `[]` if none.
    let photos: [PostPhotoDTO]
    /// When the signed photo URLs stop working; nil when there are no photos.
    let photosExpireAt: Date?
    /// Most-used first; `[]` if none. Mutable for optimistic reaction toggles.
    var reactions: [ReactionSummaryDTO]
    /// A shared workout, or nil when the post shares none.
    let workout: SharedWorkoutDTO?

    var cursor: PageCursor {
        PageCursor(before: createdAt.raw, beforeId: id)
    }

    /// Whether the photo URLs have expired (or will within `margin`), so the
    /// post or page should be refetched rather than showing broken images.
    func photosExpired(at now: Date = .now, margin: TimeInterval = 30) -> Bool {
        guard let photosExpireAt else { return false }
        return photosExpireAt.addingTimeInterval(-margin) <= now
    }
}

nonisolated struct PostPhotoDTO: Codable, Sendable, Hashable, Identifiable {
    let id: String
    /// Signed for 15 minutes. Never cache by URL — key by `id`.
    let url: String
    let width: Int
    let height: Int

    /// width / height, for laying out before the image loads.
    var aspectRatio: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }
}

/// A shared workout, as text only (ADR 001). `programName` is nil for a
/// standalone workout.
nonisolated struct SharedWorkoutDTO: Codable, Sendable, Hashable {
    let programName: String?

    /// "<name> completed a workout from <programName>", or "<name> completed a
    /// workout" for a standalone one.
    func line(authorName: String) -> String {
        if let programName, !programName.isEmpty {
            return "\(authorName) completed a workout from \(programName)"
        }
        return "\(authorName) completed a workout"
    }
}

/// One emoji's total on a post. `mine` marks the caller's own reaction.
nonisolated struct ReactionSummaryDTO: Codable, Sendable, Hashable, Identifiable {
    let emoji: String
    var count: Int
    var mine: Bool

    var id: String { emoji }
}

/// `{ posts }` from the feed and a user's posts.
nonisolated struct PostsResponseDTO: Codable, Sendable {
    let posts: [PostDTO]
}

/// `{ reactions }` from adding a reaction.
nonisolated struct ReactionsResponseDTO: Codable, Sendable {
    let reactions: [ReactionSummaryDTO]
}

/// `201 { id, width, height }` from `POST /api/post-photos`. No URL: show the
/// local copy until the post exists.
nonisolated struct UploadedPhotoDTO: Codable, Sendable, Hashable {
    let id: String
    let width: Int
    let height: Int
}

/// A who-reacted row: `PublicUser & Relationship & { reactedAt, cursorId }`.
/// The next-page cursor is `reactedAt` + `cursorId`, not the user's id.
nonisolated struct ReactorDTO: Codable, Sendable, Hashable, Identifiable {
    let user: PublicUserDTO
    var relationship: RelationshipDTO
    let reactedAt: WireTimestamp
    let cursorId: String

    var id: String { user.id }

    var cursor: PageCursor {
        PageCursor(before: reactedAt.raw, beforeId: cursorId)
    }

    init(user: PublicUserDTO, relationship: RelationshipDTO, reactedAt: WireTimestamp, cursorId: String) {
        self.user = user
        self.relationship = relationship
        self.reactedAt = reactedAt
        self.cursorId = cursorId
    }

    private enum CodingKeys: String, CodingKey {
        case reactedAt, cursorId
    }

    init(from decoder: any Decoder) throws {
        user = try PublicUserDTO(from: decoder)
        relationship = try RelationshipDTO(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reactedAt = try container.decode(WireTimestamp.self, forKey: .reactedAt)
        cursorId = try container.decode(String.self, forKey: .cursorId)
    }

    func encode(to encoder: any Encoder) throws {
        try user.encode(to: encoder)
        try relationship.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reactedAt, forKey: .reactedAt)
        try container.encode(cursorId, forKey: .cursorId)
    }
}

/// `{ users }` from who-reacted.
nonisolated struct ReactorsResponseDTO: Codable, Sendable {
    let users: [ReactorDTO]
}
