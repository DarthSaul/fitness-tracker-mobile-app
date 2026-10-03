import Foundation

// MARK: - Profile Visibility

/// Who can see a user's posts: anyone (`PUBLIC`) or accepted followers only
/// (`PRIVATE`). Every profile starts `PRIVATE`. An unrecognized value decodes
/// as `.private`, the safer reading.
nonisolated enum ProfileVisibility: String, Codable, Sendable, Hashable, CaseIterable {
    case `public` = "PUBLIC"
    case `private` = "PRIVATE"

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProfileVisibility(rawValue: raw) ?? .private
    }
}

// MARK: - Public User

/// The only shape another user ever appears in. Never carries an email.
nonisolated struct PublicUserDTO: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String?
    let avatarUrl: String?
    let profileVisibility: ProfileVisibility
    /// Every account has one. Show it as `@username` (see `handle`).
    let username: String

    var handle: String { "@\(username)" }

    /// The name when set, otherwise the handle.
    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return handle
    }
}

// MARK: - Relationship

/// One direction of a follow: none, a pending request, or an accepted follow.
/// An unrecognized value decodes as `.none`.
nonisolated enum FollowState: String, Codable, Sendable, Hashable {
    case none
    case requested
    case following

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FollowState(rawValue: raw) ?? .none
    }
}

/// The caller's follow relationship with another user.
nonisolated struct RelationshipDTO: Codable, Sendable, Hashable {
    let isSelf: Bool
    /// Me → them.
    var outgoing: FollowState
    /// Them → me.
    var incoming: FollowState
    /// Their pending request to me, to accept or decline.
    var incomingRequestId: String?
}

/// `PublicUser & Relationship`: one flat JSON object decoded into both parts.
/// Search results and who-reacted rows use this shape.
nonisolated struct UserWithRelationshipDTO: Codable, Sendable, Hashable, Identifiable {
    let user: PublicUserDTO
    var relationship: RelationshipDTO

    var id: String { user.id }

    init(user: PublicUserDTO, relationship: RelationshipDTO) {
        self.user = user
        self.relationship = relationship
    }

    init(from decoder: any Decoder) throws {
        user = try PublicUserDTO(from: decoder)
        relationship = try RelationshipDTO(from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        try user.encode(to: encoder)
        try relationship.encode(to: encoder)
    }
}

/// `PublicUser & { since }` from `GET /api/following` / `GET /api/followers`,
/// and the accepted follower from `POST /api/follow-requests/:id/accept`.
nonisolated struct FollowListUserDTO: Codable, Sendable, Hashable, Identifiable {
    let user: PublicUserDTO
    let since: Date

    var id: String { user.id }

    init(user: PublicUserDTO, since: Date) {
        self.user = user
        self.since = since
    }

    private enum CodingKeys: String, CodingKey { case since }

    init(from decoder: any Decoder) throws {
        user = try PublicUserDTO(from: decoder)
        since = try decoder.container(keyedBy: CodingKeys.self).decode(Date.self, forKey: .since)
    }

    func encode(to encoder: any Encoder) throws {
        try user.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(since, forKey: .since)
    }
}

/// `{ users: (PublicUser & Relationship)[] }` from search.
nonisolated struct UsersWithRelationshipResponseDTO: Codable, Sendable {
    let users: [UserWithRelationshipDTO]
}

/// `{ users: (PublicUser & { since })[] }` from the following / followers lists.
nonisolated struct FollowListResponseDTO: Codable, Sendable {
    let users: [FollowListUserDTO]
}
