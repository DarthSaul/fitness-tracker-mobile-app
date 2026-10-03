import Foundation

// MARK: - Profile Stats

/// The two opt-out profile stats (ADR 001 amendment) — the only
/// workout-derived values ever shown about another user.
///
/// `nil` means "don't show it" (a setting that's off, a viewer who can't see
/// the posts, no active program — deliberately indistinguishable): hide the
/// row. `0` is a real count: show "0".
nonisolated struct ProfileStatsDTO: Codable, Sendable, Hashable {
    struct ActiveProgram: Codable, Sendable, Hashable {
        let name: String
    }

    let activeProgram: ActiveProgram?
    let completedWorkoutCount: Int?

    init(activeProgram: ActiveProgram?, completedWorkoutCount: Int?) {
        self.activeProgram = activeProgram
        self.completedWorkoutCount = completedWorkoutCount
    }

    private enum CodingKeys: String, CodingKey {
        case activeProgram, completedWorkoutCount
    }

    // A missing key reads the same as `null`: hide the row.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeProgram = try container.decodeIfPresent(ActiveProgram.self, forKey: .activeProgram)
        completedWorkoutCount = try container.decodeIfPresent(Int.self, forKey: .completedWorkoutCount)
    }

    /// The row to show for the active program, or nil to hide it.
    var activeProgramRow: String? { activeProgram?.name }

    /// The row to show for the workout count, or nil to hide it. `0` shows "0".
    var workoutCountRow: String? { completedWorkoutCount.map(String.init) }
}

// MARK: - Profile

/// `GET /api/users/:id`: `PublicUser & Relationship & ProfileStats` plus the
/// bio and follow counts. The caller's own id works for "My profile".
nonisolated struct UserProfileDTO: Codable, Sendable, Hashable, Identifiable {
    let user: PublicUserDTO
    var relationship: RelationshipDTO
    let stats: ProfileStatsDTO
    let bio: String?
    /// Accepted follows only.
    var followerCount: Int
    var followingCount: Int

    var id: String { user.id }

    init(
        user: PublicUserDTO,
        relationship: RelationshipDTO,
        stats: ProfileStatsDTO,
        bio: String?,
        followerCount: Int,
        followingCount: Int
    ) {
        self.user = user
        self.relationship = relationship
        self.stats = stats
        self.bio = bio
        self.followerCount = followerCount
        self.followingCount = followingCount
    }

    private enum CodingKeys: String, CodingKey {
        case bio, followerCount, followingCount
    }

    init(from decoder: any Decoder) throws {
        user = try PublicUserDTO(from: decoder)
        relationship = try RelationshipDTO(from: decoder)
        stats = try ProfileStatsDTO(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        followerCount = try container.decode(Int.self, forKey: .followerCount)
        followingCount = try container.decode(Int.self, forKey: .followingCount)
    }

    func encode(to encoder: any Encoder) throws {
        try user.encode(to: encoder)
        try relationship.encode(to: encoder)
        try stats.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encode(followerCount, forKey: .followerCount)
        try container.encode(followingCount, forKey: .followingCount)
    }

    /// Whether the posts tab will be refused (`403 profile_private`), so the
    /// lock state can show without making the call.
    var postsAreLocked: Bool {
        SocialRules.postsAreLocked(
            visibility: user.profileVisibility,
            relationship: relationship
        )
    }
}

// MARK: - Rules

/// Client-side predictions of server rules, kept in one place so screens
/// and tests agree.
nonisolated enum SocialRules {
    /// A user's posts are visible to themselves, to anyone when the profile is
    /// `PUBLIC`, and to accepted followers when it's `PRIVATE`.
    static func postsAreLocked(visibility: ProfileVisibility, relationship: RelationshipDTO) -> Bool {
        !relationship.isSelf && visibility == .private && relationship.outgoing != .following
    }

    /// Post bodies are 0–2,000 characters after trimming, counted in UTF-16
    /// code units the way the server's JavaScript `.length` does.
    static let postBodyMax = 2000

    /// A post's trimmed body length as the server counts it.
    static func postBodyLength(_ body: String) -> Int {
        body.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
    }

    /// Bios are at most 100 Unicode code points after trimming — what the
    /// database's `char_length` counts. Not `String.count`: 👍🏽 is one
    /// character but two code points.
    static let bioMax = 100

    static func bioLength(_ bio: String) -> Int {
        bio.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }

    /// Report details: up to 1,000 characters.
    static let reportDetailsMax = 1000

    /// Search `q`: 2–100 characters after trimming and dropping one leading `@`.
    static func normalizedSearchQuery(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutAt = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        guard (2...100).contains(withoutAt.count) else { return nil }
        return trimmed
    }
}
