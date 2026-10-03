import Foundation
import Testing
@testable import FitnessTracker

@Suite("Social DTO decoding")
struct SocialDTOTests {
    // MARK: - Timestamps

    @Test("dates with milliseconds decode, keeping the milliseconds")
    func millisecondDates() throws {
        struct Box: Decodable { let at: Date }
        let box = try SocialFixtures.decode(Box.self, #"{"at":"2026-10-02T12:00:00.123Z"}"#)
        let expected = try #require(JSONCoding.parseISO8601("2026-10-02T12:00:00Z"))
        #expect(abs(box.at.timeIntervalSince(expected) - 0.123) < 0.0005)
    }

    @Test("dates without fractional seconds still decode")
    func wholeSecondDates() throws {
        struct Box: Decodable { let at: Date }
        _ = try SocialFixtures.decode(Box.self, #"{"at":"2026-10-02T12:00:00Z"}"#)
    }

    @Test("WireTimestamp keeps the exact string for cursors")
    func wireTimestampKeepsRaw() throws {
        let post = try SocialFixtures.decode(PostDTO.self, SocialFixtures.postJSON(createdAt: "2026-10-02T12:00:00.120Z"))
        #expect(post.createdAt.raw == "2026-10-02T12:00:00.120Z")
        #expect(post.cursor == PageCursor(before: "2026-10-02T12:00:00.120Z", beforeId: "post-1"))
    }

    // MARK: - Post

    @Test("a full post decodes, ignoring unknown keys")
    func fullPost() throws {
        let json = SocialFixtures.postJSON(
            photos: #"[{"id":"ph-1","url":"https://x/1.jpg","width":2048,"height":1536,"blurhash":"new-field"}]"#,
            photosExpireAt: "2026-10-02T12:15:00.000Z",
            reactions: #"[{"emoji":"🔥","count":3,"mine":true},{"emoji":"💪","count":1,"mine":false}]"#,
            workout: #"{"programName":"Arm Farm 2"}"#,
            editedAt: "2026-10-02T12:05:00.000Z"
        ).replacingOccurrences(of: "\"isMine\"", with: "\"futureKey\":42,\"isMine\"")

        let post = try SocialFixtures.decode(PostDTO.self, json)
        #expect(post.author.handle == "@ann")
        #expect(post.photos.count == 1)
        #expect(post.photos[0].aspectRatio == CGFloat(2048) / CGFloat(1536))
        #expect(post.reactions.map(\.emoji) == ["🔥", "💪"])
        #expect(post.reactions[0].mine)
        #expect(post.editedAt != nil)
        #expect(post.workout?.line(authorName: "Ann") == "Ann completed a workout from Arm Farm 2")
    }

    @Test("a standalone workout share reads without a program name")
    func standaloneShareLine() throws {
        let post = try SocialFixtures.decode(PostDTO.self, SocialFixtures.postJSON(body: "", workout: #"{"programName":null}"#))
        #expect(post.workout?.line(authorName: "Ann") == "Ann completed a workout")
        #expect(post.body.isEmpty)
    }

    @Test("photo URLs count as expired from photosExpireAt (with a safety margin)")
    func photoExpiry() throws {
        let post = try SocialFixtures.decode(
            PostDTO.self,
            SocialFixtures.postJSON(photosExpireAt: "2026-10-02T12:15:00.000Z")
        )
        let expiry = try #require(post.photosExpireAt)
        #expect(!post.photosExpired(at: expiry.addingTimeInterval(-120)))
        #expect(post.photosExpired(at: expiry.addingTimeInterval(-10)))
        #expect(post.photosExpired(at: expiry.addingTimeInterval(60)))

        let textOnly = try SocialFixtures.decode(PostDTO.self, SocialFixtures.postJSON())
        #expect(!textOnly.photosExpired(at: .distantFuture))
    }

    // MARK: - Users

    @Test("PublicUser & Relationship decodes from one flat object")
    func flatUserWithRelationship() throws {
        let json = """
        {"id":"u1","name":null,"avatarUrl":null,"profileVisibility":"PRIVATE","username":"saul.g",
         "isSelf":false,"outgoing":"requested","incoming":"following","incomingRequestId":null}
        """
        let row = try SocialFixtures.decode(UserWithRelationshipDTO.self, json)
        #expect(row.user.profileVisibility == .private)
        #expect(row.user.displayName == "@saul.g")
        #expect(row.relationship.outgoing == .requested)
        #expect(row.relationship.incoming == .following)
    }

    @Test("unknown enum values fall back safely")
    func unknownEnumFallbacks() throws {
        let json = """
        {"id":"u1","name":"A","avatarUrl":null,"profileVisibility":"FRIENDS_ONLY","username":"a",
         "isSelf":false,"outgoing":"blocked","incoming":"none","incomingRequestId":null}
        """
        let row = try SocialFixtures.decode(UserWithRelationshipDTO.self, json)
        #expect(row.user.profileVisibility == .private)
        #expect(row.relationship.outgoing == .none)
    }

    @Test("a who-reacted row pages on reactedAt + cursorId, not the user id")
    func reactorCursor() throws {
        let json = """
        {"users":[{"id":"u1","name":"A","avatarUrl":null,"profileVisibility":"PUBLIC","username":"a",
         "isSelf":true,"outgoing":"none","incoming":"none","incomingRequestId":null,
         "reactedAt":"2026-10-02T12:00:00.456Z","cursorId":"reaction-9"}]}
        """
        let page = try SocialFixtures.decode(ReactorsResponseDTO.self, json)
        #expect(page.users[0].cursor == PageCursor(before: "2026-10-02T12:00:00.456Z", beforeId: "reaction-9"))
        #expect(page.users[0].relationship.isSelf)
    }

    // MARK: - Profile + stats

    private func profileJSON(stats: String) -> String {
        """
        {"id":"u1","name":"Ann","avatarUrl":null,"profileVisibility":"PRIVATE","username":"ann",
         "isSelf":false,"outgoing":"none","incoming":"none","incomingRequestId":"req-1",
         "bio":"Lifting","followerCount":0,"followingCount":12\(stats)}
        """
    }

    @Test("profile stats: null hides the row, 0 is shown")
    func profileStatsNullVsZero() throws {
        let zero = try SocialFixtures.decode(
            UserProfileDTO.self,
            profileJSON(stats: #","activeProgram":{"name":"Arm Farm 2"},"completedWorkoutCount":0"#)
        )
        #expect(zero.stats.activeProgramRow == "Arm Farm 2")
        #expect(zero.stats.workoutCountRow == "0")

        let hidden = try SocialFixtures.decode(
            UserProfileDTO.self,
            profileJSON(stats: #","activeProgram":null,"completedWorkoutCount":null"#)
        )
        #expect(hidden.stats.activeProgramRow == nil)
        #expect(hidden.stats.workoutCountRow == nil)

        // A missing key reads like null.
        let missing = try SocialFixtures.decode(UserProfileDTO.self, profileJSON(stats: ""))
        #expect(missing.stats.workoutCountRow == nil)
        #expect(missing.relationship.incomingRequestId == "req-1")
        #expect(missing.followingCount == 12)
    }

    @Test("lock state is predicted from visibility and the outgoing follow")
    func postsLockRule() {
        func relationship(_ outgoing: FollowState, isSelf: Bool = false) -> RelationshipDTO {
            RelationshipDTO(isSelf: isSelf, outgoing: outgoing, incoming: .none, incomingRequestId: nil)
        }
        #expect(SocialRules.postsAreLocked(visibility: .private, relationship: relationship(.none)))
        #expect(SocialRules.postsAreLocked(visibility: .private, relationship: relationship(.requested)))
        #expect(!SocialRules.postsAreLocked(visibility: .private, relationship: relationship(.following)))
        #expect(!SocialRules.postsAreLocked(visibility: .public, relationship: relationship(.none)))
        #expect(!SocialRules.postsAreLocked(visibility: .private, relationship: relationship(.none, isSelf: true)))
    }

    // MARK: - Counting

    @Test("bio length counts Unicode code points, after trimming")
    func bioCodePoints() {
        #expect(SocialRules.bioLength("💪") == 1)
        #expect(SocialRules.bioLength("👨‍👩‍👧") == 5)
        #expect(SocialRules.bioLength("🇬🇧") == 2)
        #expect(SocialRules.bioLength("👍🏽") == 2)
        #expect(SocialRules.bioLength("  abc  ") == 3)
        // String.count would say 1 here; the server counts 5.
        #expect("👨‍👩‍👧".count == 1)
    }

    @Test("post body length counts UTF-16 code units, like the server's .length")
    func postBodyLength() {
        #expect(SocialRules.postBodyLength("💪") == 2)
        #expect(SocialRules.postBodyLength("  hi \n") == 2)
    }

    @Test("search query must be 2–100 characters after dropping a leading @")
    func searchQueryRule() {
        #expect(SocialRules.normalizedSearchQuery("a") == nil)
        #expect(SocialRules.normalizedSearchQuery("@a") == nil)
        #expect(SocialRules.normalizedSearchQuery("  @sa ") == "@sa")
        #expect(SocialRules.normalizedSearchQuery("saul") == "saul")
        #expect(SocialRules.normalizedSearchQuery(String(repeating: "a", count: 101)) == nil)
    }

    // MARK: - Request bodies

    @Test("a workout share sends exactly one session id")
    func createPostShareBody() throws {
        let program = CreatePostBody(body: "  ", sharing: .program(sessionId: "ws-1"))
        let programJSON = String(decoding: try JSONCoding.encoder.encode(program), as: UTF8.self)
        #expect(programJSON.contains("\"workoutSessionId\":\"ws-1\""))
        #expect(!programJSON.contains("standaloneSessionId"))
        #expect(!programJSON.contains("\"body\""))

        let standalone = CreatePostBody(body: "Done", photoIds: ["p1", "p2"], sharing: .standalone(sessionId: "ss-1"))
        let standaloneJSON = String(decoding: try JSONCoding.encoder.encode(standalone), as: UTF8.self)
        #expect(standaloneJSON.contains("\"standaloneSessionId\":\"ss-1\""))
        #expect(!standaloneJSON.contains("workoutSessionId"))
        #expect(standaloneJSON.contains("\"photoIds\":[\"p1\",\"p2\"]"))
    }

    @Test("a report names exactly one of post or user")
    func reportBody() throws {
        let json = String(decoding: try JSONCoding.encoder.encode(ReportBody.post("p1", reason: .selfHarm, details: "  ")), as: UTF8.self)
        #expect(json.contains("\"postId\":\"p1\""))
        #expect(json.contains("\"reason\":\"SELF_HARM\""))
        #expect(!json.contains("userId"))
        #expect(!json.contains("details"))
    }

    @Test("report reasons are listed in contract order")
    func reportReasonOrder() {
        #expect(ReportReason.allCases.map(\.rawValue) == [
            "SPAM", "HARASSMENT", "HATE", "SEXUAL_CONTENT", "VIOLENCE", "SELF_HARM", "IMPERSONATION", "OTHER",
        ])
    }
}
