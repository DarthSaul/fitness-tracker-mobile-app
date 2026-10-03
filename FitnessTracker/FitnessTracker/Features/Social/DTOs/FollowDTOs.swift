import Foundation

// MARK: - Follow

/// `POST /api/following` → `{ status: 'following' }` for a `PUBLIC` profile or
/// `{ status: 'requested', requestId }` for a `PRIVATE` one. `201` when new,
/// `200` when it already existed — both are success.
nonisolated struct FollowResponseDTO: Codable, Sendable, Hashable {
    let status: FollowState
    let requestId: String?
}

// MARK: - Follow Requests

nonisolated enum FollowRequestDirection: String, Codable, Sendable, Hashable {
    case incoming
    case outgoing
}

nonisolated struct FollowRequestDTO: Codable, Sendable, Hashable, Identifiable {
    let id: String
    /// Always the other person.
    let user: PublicUserDTO
    let direction: FollowRequestDirection
    let createdAt: Date
}

nonisolated struct FollowRequestsResponseDTO: Codable, Sendable {
    let requests: [FollowRequestDTO]
}

/// `POST /api/follow-requests/:id/accept` → `{ follower }`.
nonisolated struct AcceptFollowRequestResponseDTO: Codable, Sendable {
    let follower: FollowListUserDTO
}

// MARK: - Blocks

/// A row in `GET /api/blocks`: `PublicUser & { blockedAt }`.
nonisolated struct BlockedUserDTO: Codable, Sendable, Hashable, Identifiable {
    let user: PublicUserDTO
    let blockedAt: Date

    var id: String { user.id }

    init(user: PublicUserDTO, blockedAt: Date) {
        self.user = user
        self.blockedAt = blockedAt
    }

    private enum CodingKeys: String, CodingKey { case blockedAt }

    init(from decoder: any Decoder) throws {
        user = try PublicUserDTO(from: decoder)
        blockedAt = try decoder.container(keyedBy: CodingKeys.self).decode(Date.self, forKey: .blockedAt)
    }

    func encode(to encoder: any Encoder) throws {
        try user.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blockedAt, forKey: .blockedAt)
    }
}

nonisolated struct BlockedUsersResponseDTO: Codable, Sendable {
    let users: [BlockedUserDTO]
}

/// `POST /api/blocks` → `{ userId, blockedAt }`.
nonisolated struct BlockResponseDTO: Codable, Sendable, Hashable {
    let userId: String
    let blockedAt: Date
}

// MARK: - Reports

/// Report reasons, in the order the contract says to show them.
nonisolated enum ReportReason: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case spam = "SPAM"
    case harassment = "HARASSMENT"
    case hate = "HATE"
    case sexualContent = "SEXUAL_CONTENT"
    case violence = "VIOLENCE"
    case selfHarm = "SELF_HARM"
    case impersonation = "IMPERSONATION"
    case other = "OTHER"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harassment or bullying"
        case .hate: "Hate speech"
        case .sexualContent: "Sexual content"
        case .violence: "Violence"
        case .selfHarm: "Self-harm"
        case .impersonation: "Impersonation"
        case .other: "Something else"
        }
    }
}

/// `POST /api/reports` → `{ id }`, `201` new or `200` already reported.
nonisolated struct ReportResponseDTO: Codable, Sendable, Hashable {
    let id: String
}

// MARK: - Usernames

nonisolated enum UsernameUnavailableReason: String, Codable, Sendable, Hashable {
    case invalid
    case reserved
    case taken

    /// Unknown reasons read as `invalid` so the field still blocks saving.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UsernameUnavailableReason(rawValue: raw) ?? .invalid
    }
}

/// `GET /api/users/username-available`.
nonisolated struct UsernameAvailabilityDTO: Codable, Sendable, Hashable {
    let available: Bool
    let reason: UsernameUnavailableReason?
}
