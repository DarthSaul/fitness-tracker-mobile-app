import Foundation

/// What an `APIError` means for the UI, per the status codes the social and
/// notifications contracts ask clients to branch on. Screens switch on this
/// instead of on raw status codes.
///
/// `200` vs `201` (idempotent creates) and `204` (deletes, including deleting
/// nothing) never get here: `APIClient` treats every 2xx as success.
nonisolated enum APIFailure: Equatable, Sendable {
    /// The refresh token is dead — run the forced sign-out.
    case unauthorized
    /// `404`: missing, not yours, or hidden by a block. Deliberately
    /// indistinguishable, so show it as gone and never as "blocked".
    case notFound
    /// `403` with `data.code: 'profile_private'` on a user's posts.
    case profilePrivate
    /// `409`: a state conflict. `message` is the server's reason, e.g.
    /// "Workout already shared" or "Username taken".
    case conflict(message: String?)
    /// `413`: a photo over the 4 MB upload limit.
    case payloadTooLarge
    /// `415`: a photo that isn't JPEG, PNG or WebP.
    case unsupportedMediaType
    /// `429`: rate limited. Show "try again later"; never auto-retry.
    case rateLimited
    /// `400`: a request the server rejected as invalid.
    case invalid(message: String?)
    /// No connection, timeout, etc.
    case offline
    case other(message: String?)

    init(_ error: APIError) {
        switch error {
        case .unauthorized:
            self = .unauthorized
        case .httpError(let status, let message, let data):
            switch status {
            case 401: self = .unauthorized
            case 403 where APIError.decodeServerErrorCode(from: data) == "profile_private":
                self = .profilePrivate
            case 404: self = .notFound
            case 409: self = .conflict(message: message)
            case 413: self = .payloadTooLarge
            case 415: self = .unsupportedMediaType
            case 429: self = .rateLimited
            case 400: self = .invalid(message: message)
            default: self = .other(message: message)
            }
        case .network:
            self = .offline
        case .decoding, .unknown, .missingHandler:
            self = .other(message: nil)
        }
    }

    init(_ error: any Error) {
        self = (error as? APIError).map(APIFailure.init) ?? .other(message: nil)
    }

    /// User-facing text. Screens with a more specific context (e.g. "This
    /// post was deleted") can override individual cases.
    var message: String {
        switch self {
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .notFound:
            return "This is no longer available."
        case .profilePrivate:
            return "This account is private."
        case .conflict(let message):
            return Self.conflictMessage(message)
        case .payloadTooLarge:
            return "That photo is too large. Try a smaller one."
        case .unsupportedMediaType:
            return "That image format isn't supported."
        case .rateLimited:
            return "You're doing that too often. Try again later."
        case .invalid(let message):
            return message ?? "Something about that request wasn't right."
        case .offline:
            return "You appear to be offline. Check your connection and try again."
        case .other(let message):
            return message ?? "Something went wrong. Please try again."
        }
    }

    /// Friendlier wording for the `409` reasons the contracts name. Unknown
    /// reasons fall back to the server's text.
    private static func conflictMessage(_ serverMessage: String?) -> String {
        switch serverMessage {
        case "Workout already shared":
            return "You've already shared this workout."
        case "Workout is not completed":
            return "Only completed workouts can be shared."
        case "Username taken":
            return "That username is taken."
        case let message? where message.hasPrefix("At most") && message.contains("reactions"):
            return "You can add up to 10 different reactions to a post."
        case let message?:
            return message
        case nil:
            return "That conflicts with a recent change. Refresh and try again."
        }
    }
}
