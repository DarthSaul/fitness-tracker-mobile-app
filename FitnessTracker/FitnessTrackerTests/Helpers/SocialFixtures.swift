import Foundation
@testable import FitnessTracker

/// Wire-exact JSON for social and notification payloads, shaped like the
/// server's responses (API_CONTRACT_SOCIAL.md / API_CONTRACT_NOTIFICATIONS.md),
/// so decoding tests exercise the real format rather than a re-encoded DTO.
enum SocialFixtures {
    static func publicUserJSON(
        id: String = "user-ann",
        name: String? = "Ann",
        username: String = "ann",
        visibility: String = "PUBLIC"
    ) -> String {
        let nameJSON = name.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(id)","name":\(nameJSON),"avatarUrl":null,"profileVisibility":"\(visibility)","username":"\(username)"}
        """
    }

    /// A post with every field populated the way the server sends it.
    /// `createdAt` keeps milliseconds so cursor tests can check they survive.
    static func postJSON(
        id: String = "post-1",
        authorId: String = "user-ann",
        body: String = "Leg day done",
        createdAt: String = "2026-10-02T12:00:00.123Z",
        isMine: Bool = false,
        photos: String = "[]",
        photosExpireAt: String? = nil,
        reactions: String = "[]",
        workout: String = "null",
        editedAt: String? = nil
    ) -> String {
        let expires = photosExpireAt.map { "\"\($0)\"" } ?? "null"
        let edited = editedAt.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(id)","author":\(publicUserJSON(id: authorId)),"body":"\(body)","createdAt":"\(createdAt)",\
        "editedAt":\(edited),"isMine":\(isMine),"photos":\(photos),"photosExpireAt":\(expires),\
        "reactions":\(reactions),"workout":\(workout)}
        """
    }

    static func postsPageJSON(_ posts: [String]) -> String {
        "{\"posts\":[\(posts.joined(separator: ","))]}"
    }

    static func notificationJSON(
        id: String = "n-1",
        type: String = "POST_REACTION",
        status: String = "unread",
        createdAt: String = "2026-10-02T12:00:00.000Z",
        actor: String? = publicUserJSON(),
        target: String = #"{"postId":"post-1"}"#,
        data: String = #"{"emoji":"🔥"}"#
    ) -> String {
        """
        {"id":"\(id)","type":"\(type)","status":"\(status)","createdAt":"\(createdAt)","readAt":null,\
        "actor":\(actor ?? "null"),"target":\(target),"data":\(data)}
        """
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoding.decoder.decode(T.self, from: Data(json.utf8))
    }
}
