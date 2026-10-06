import Foundation

// MARK: - HTTP Method
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

// MARK: - Endpoint
enum APIEndpoint {
    // Auth
    case appleSignIn(AppleSignInBody)
    case googleSignIn(GoogleSignInBody)
    case emailSignIn(EmailSignInBody)
    case emailSignUp(EmailSignUpBody)
    case resendConfirmationEmail(ResendConfirmationBody)
    /// Reuses the web reset route — it's session-agnostic and the emailed
    /// link opens the web reset page (no native variant exists).
    case requestPasswordReset(PasswordResetBody)
    case refreshToken(RefreshTokenBody)
    /// Native logout: revokes the refresh token and, on a user-initiated
    /// sign-out, the device's push token. Never sent on a forced sign-out or
    /// after account deletion.
    case logout(LogoutBody)
    case getMe
    /// PATCH /api/auth/me with any subset of the settings fields.
    case updateMe(UpdateMeBody)
    /// Permanently deletes the account and all server data. The server
    /// cascades identities, workout history, programs, refresh tokens, and
    /// device tokens in one operation — do NOT follow up with `.logout` or
    /// `.unregisterDevice` (both would 401 against the deleted account).
    case deleteAccount

    // Programs
    case getPrograms
    case getProgram(id: String)
    case getProgramDay(id: String)

    // User Programs
    case getUserPrograms
    case getActiveUserProgram
    case getActiveProgramSessions
    case saveProgram(programId: String)
    case unsaveProgram(userProgramId: String)
    case activateProgram(userProgramId: String)
    case deactivateProgram(userProgramId: String)
    /// Ends an open run early (terminal — unlike deactivate, which pauses).
    case completeProgram(userProgramId: String)

    // Scheduled Workouts
    case getScheduledWorkouts(userProgramId: String, from: Date?, to: Date?)
    case scheduleWorkout(ScheduleWorkoutBody)
    case unscheduleWorkout(id: String)

    // Workouts
    case getActiveWorkout
    /// Unified history across program and standalone completions. `type`
    /// narrows to one kind; nil interleaves both, newest first.
    case getHistory(type: HistoryTypeFilter?, limit: Int?, before: Date?, beforeId: String?)
    /// Every completed session's `completedAt` (program + standalone),
    /// ascending — instants, so the client buckets them into local days.
    case getHistoryDates
    case createWorkout(CreateWorkoutBody?)
    case getWorkout(id: String)
    case abandonWorkout(id: String)
    case updateWorkoutNotes(id: String, body: UpdateWorkoutNotesBody)
    /// PATCH /api/workouts/:id with just `{ completedAt }`. Used to edit the
    /// date of an already-completed session — the `/complete` endpoint 409s on
    /// re-completion, so date-only edits route here instead.
    case updateWorkoutDate(id: String, body: UpdateWorkoutDateBody)
    case completeWorkout(id: String, body: CompleteWorkoutBody?)
    case recordSet(workoutId: String, body: RecordSetBody)
    case updateSet(workoutId: String, setId: String, body: UpdateSetBody)
    case deleteSet(workoutId: String, setId: String)
    case addExtraSet(workoutId: String, programExerciseId: String, body: AddExtraSetBody)
    case deleteExtraSet(workoutId: String, completedSetId: String)
    case swapExercise(workoutId: String, programExerciseId: String, body: SwapExerciseBody)
    case addAdHocSet(workoutId: String, body: AddAdHocSetBody)

    // Core workout (per-session timed circuit)
    case saveCoreWorkout(sessionId: String, body: SaveCoreWorkoutBody)
    case completeCoreWorkout(sessionId: String, body: CompleteCoreWorkoutBody?)
    case deleteCoreWorkout(sessionId: String)

    // Standalone workouts (catalog)
    case getStandaloneWorkouts(category: String?)
    case getStandaloneWorkout(id: String)

    // Standalone workout sessions
    case createStandaloneSession(CreateStandaloneSessionBody)
    case getActiveStandaloneSessions
    case getStandaloneSession(id: String)
    case recordStandaloneSet(sessionId: String, body: RecordStandaloneSetBody)
    case updateStandaloneSet(sessionId: String, setId: String, body: UpdateSetBody)
    case deleteStandaloneSet(sessionId: String, setId: String)
    case completeStandaloneSession(id: String, body: CompleteWorkoutBody?)
    case abandonStandaloneSession(id: String)

    // Exercises
    case getExercises(search: String?)
    case getCoreExercises
    case getExerciseNotes(exerciseId: String)
    case getExerciseInfo(exerciseId: String)
    case updateExerciseNotes(exerciseId: String, body: UpdateExerciseNotesBody)

    // Analytics
    case getDashboard(timeZone: String?)
    case getAnalyticsExercises
    case getAnalyticsExercise(id: String)

    // Devices
    case registerDevice(DeviceRegistrationBody)
    case unregisterDevice(id: String)

    // Feedback
    case getFeedback
    /// POST /api/feedback. Body is `multipart/form-data` (built separately by
    /// `APIClient.sendMultipart`) so this case carries no Encodable payload.
    case createFeedback
    case updateFeedback(id: String, body: UpdateFeedbackBody)

    // Social — users
    case searchUsers(query: String)
    case getUser(id: String)
    case getUserPosts(userId: String, page: PageQuery)
    case checkUsernameAvailability(username: String)

    // Social — follows
    case follow(FollowBody)
    /// Unfollow, or cancel my pending request. `204` even when not following.
    case unfollow(userId: String)
    case getFollowing
    case getFollowers
    case removeFollower(userId: String)
    case getFollowRequests(direction: FollowRequestDirection)
    case acceptFollowRequest(id: String)
    /// Decline (as the followee) or cancel (as the requester).
    case deleteFollowRequest(id: String)

    // Social — feed and posts
    case getFeed(page: PageQuery)
    /// POST /api/post-photos. Multipart (field `photo`), built by
    /// `APIClient.sendMultipart`, so this case carries no Encodable payload.
    case uploadPostPhoto
    case createPost(CreatePostBody)
    case getPost(id: String)
    case updatePost(id: String, body: UpdatePostBody)
    case deletePost(id: String)

    // Social — reactions. `emoji` is the raw emoji: the URL builder
    // percent-encodes it (👍 → %F0%9F%91%8D). Pre-encoding would double-encode.
    case addReaction(postId: String, emoji: String)
    case removeReaction(postId: String, emoji: String)
    case getReactors(postId: String, emoji: String, page: PageQuery)

    // Social — safety
    case getBlocks
    case block(BlockBody)
    case unblock(userId: String)
    case report(ReportBody)

    // Notifications
    case getNotifications(status: NotificationListFilter, page: PageQuery)
    case getUnreadNotificationCount
    case updateNotification(id: String, body: UpdateNotificationBody)
    case markAllNotificationsRead(MarkAllReadBody)
    case getNotificationPreferences
    case updateNotificationPreferences(UpdateNotificationPreferencesBody)
}

// MARK: - Request Building
extension APIEndpoint {
    var path: String {
        switch self {
        // Auth
        case .appleSignIn: return "/api/auth/native/apple"
        case .googleSignIn: return "/api/auth/native/google"
        case .emailSignIn: return "/api/auth/native/email/signin"
        case .emailSignUp: return "/api/auth/native/email/signup"
        case .resendConfirmationEmail: return "/api/auth/native/email/resend-confirmation"
        case .requestPasswordReset: return "/api/auth/email/reset-password"
        case .refreshToken: return "/api/auth/refresh"
        case .logout: return "/api/auth/logout"
        case .getMe: return "/api/auth/me"
        case .updateMe: return "/api/auth/me"
        case .deleteAccount: return "/api/auth/me"

        // Programs
        case .getPrograms: return "/api/programs"
        case .getProgram(let id): return "/api/programs/\(id)"
        case .getProgramDay(let id): return "/api/programs/days/\(id)"

        // User Programs
        case .getUserPrograms: return "/api/user-programs"
        case .getActiveUserProgram: return "/api/user-programs/active"
        case .getActiveProgramSessions: return "/api/user-programs/active/sessions"
        case .saveProgram: return "/api/user-programs"
        case .unsaveProgram(let id): return "/api/user-programs/\(id)"
        case .activateProgram(let id): return "/api/user-programs/\(id)/activate"
        case .deactivateProgram(let id): return "/api/user-programs/\(id)/deactivate"
        case .completeProgram(let id): return "/api/user-programs/\(id)/complete"

        // Scheduled Workouts
        case .getScheduledWorkouts: return "/api/scheduled-workouts"
        case .scheduleWorkout: return "/api/scheduled-workouts"
        case .unscheduleWorkout(let id): return "/api/scheduled-workouts/\(id)"

        // Workouts
        case .getActiveWorkout: return "/api/workouts/active"
        case .getHistory: return "/api/history"
        case .getHistoryDates: return "/api/history/dates"
        case .createWorkout: return "/api/workouts"
        case .getWorkout(let id): return "/api/workouts/\(id)"
        case .abandonWorkout(let id): return "/api/workouts/\(id)"
        case .updateWorkoutNotes(let id, _): return "/api/workouts/\(id)"
        case .updateWorkoutDate(let id, _): return "/api/workouts/\(id)"
        case .completeWorkout(let id, _): return "/api/workouts/\(id)/complete"
        case .recordSet(let id, _): return "/api/workouts/\(id)/sets"
        case .updateSet(let workoutId, let setId, _): return "/api/workouts/\(workoutId)/sets/\(setId)"
        case .deleteSet(let workoutId, let setId): return "/api/workouts/\(workoutId)/sets/\(setId)"
        case .addExtraSet(let workoutId, let programExerciseId, _):
            return "/api/workouts/\(workoutId)/exercises/\(programExerciseId)/extra-sets"
        case .deleteExtraSet(let workoutId, let completedSetId):
            return "/api/workouts/\(workoutId)/extra-sets/\(completedSetId)"
        case .swapExercise(let workoutId, let programExerciseId, _):
            return "/api/workouts/\(workoutId)/exercises/\(programExerciseId)/swap"
        case .addAdHocSet(let workoutId, _): return "/api/workouts/\(workoutId)/ad-hoc-sets"
        case .saveCoreWorkout(let sessionId, _): return "/api/workouts/\(sessionId)/core-workout"
        case .completeCoreWorkout(let sessionId, _): return "/api/workouts/\(sessionId)/core-workout/complete"
        case .deleteCoreWorkout(let sessionId): return "/api/workouts/\(sessionId)/core-workout"

        // Standalone workouts
        case .getStandaloneWorkouts: return "/api/standalone-workouts"
        case .getStandaloneWorkout(let id): return "/api/standalone-workouts/\(id)"
        case .createStandaloneSession: return "/api/standalone-workout-sessions"
        case .getActiveStandaloneSessions: return "/api/standalone-workout-sessions/active"
        case .getStandaloneSession(let id): return "/api/standalone-workout-sessions/\(id)"
        case .recordStandaloneSet(let sessionId, _): return "/api/standalone-workout-sessions/\(sessionId)/sets"
        case .updateStandaloneSet(let sessionId, let setId, _):
            return "/api/standalone-workout-sessions/\(sessionId)/sets/\(setId)"
        case .deleteStandaloneSet(let sessionId, let setId):
            return "/api/standalone-workout-sessions/\(sessionId)/sets/\(setId)"
        case .completeStandaloneSession(let id, _): return "/api/standalone-workout-sessions/\(id)/complete"
        case .abandonStandaloneSession(let id): return "/api/standalone-workout-sessions/\(id)"

        // Exercises
        case .getExercises: return "/api/exercises"
        case .getCoreExercises: return "/api/exercises/core"
        case .getExerciseNotes(let id): return "/api/exercises/\(id)/notes"
        case .getExerciseInfo(let id): return "/api/exercises/\(id)/info"
        case .updateExerciseNotes(let id, _): return "/api/exercises/\(id)/notes"

        // Analytics
        case .getDashboard: return "/api/analytics/dashboard"
        case .getAnalyticsExercises: return "/api/analytics/exercises"
        case .getAnalyticsExercise(let id): return "/api/analytics/exercises/\(id)"

        // Devices
        case .registerDevice: return "/api/devices/register"
        case .unregisterDevice(let id): return "/api/devices/\(id)"

        // Feedback
        case .getFeedback: return "/api/feedback"
        case .createFeedback: return "/api/feedback"
        case .updateFeedback(let id, _): return "/api/feedback/\(id)"

        // Social — users
        case .searchUsers: return "/api/users/search"
        case .getUser(let id): return "/api/users/\(id)"
        case .getUserPosts(let userId, _): return "/api/users/\(userId)/posts"
        case .checkUsernameAvailability: return "/api/users/username-available"

        // Social — follows
        case .follow: return "/api/following"
        case .unfollow(let userId): return "/api/following/\(userId)"
        case .getFollowing: return "/api/following"
        case .getFollowers: return "/api/followers"
        case .removeFollower(let userId): return "/api/followers/\(userId)"
        case .getFollowRequests: return "/api/follow-requests"
        case .acceptFollowRequest(let id): return "/api/follow-requests/\(id)/accept"
        case .deleteFollowRequest(let id): return "/api/follow-requests/\(id)"

        // Social — feed and posts
        case .getFeed: return "/api/feed"
        case .uploadPostPhoto: return "/api/post-photos"
        case .createPost: return "/api/posts"
        case .getPost(let id): return "/api/posts/\(id)"
        case .updatePost(let id, _): return "/api/posts/\(id)"
        case .deletePost(let id): return "/api/posts/\(id)"

        // Social — reactions
        case .addReaction(let postId, let emoji),
             .removeReaction(let postId, let emoji),
             .getReactors(let postId, let emoji, _):
            return "/api/posts/\(postId)/reactions/\(emoji)"

        // Social — safety
        case .getBlocks: return "/api/blocks"
        case .block: return "/api/blocks"
        case .unblock(let userId): return "/api/blocks/\(userId)"
        case .report: return "/api/reports"

        // Notifications
        case .getNotifications: return "/api/notifications"
        case .getUnreadNotificationCount: return "/api/notifications/unread-count"
        case .updateNotification(let id, _): return "/api/notifications/\(id)"
        case .markAllNotificationsRead: return "/api/notifications/read-all"
        case .getNotificationPreferences, .updateNotificationPreferences:
            return "/api/notifications/preferences"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getMe,
             .getPrograms, .getProgram, .getProgramDay,
             .getUserPrograms, .getActiveUserProgram, .getActiveProgramSessions,
             .getScheduledWorkouts,
             .getActiveWorkout, .getHistory, .getHistoryDates, .getWorkout,
             .getStandaloneWorkouts, .getStandaloneWorkout,
             .getActiveStandaloneSessions, .getStandaloneSession,
             .getExercises, .getCoreExercises, .getExerciseNotes, .getExerciseInfo,
             .getDashboard, .getAnalyticsExercises, .getAnalyticsExercise,
             .getFeedback,
             .searchUsers, .getUser, .getUserPosts, .checkUsernameAvailability,
             .getFollowing, .getFollowers, .getFollowRequests,
             .getFeed, .getPost, .getReactors, .getBlocks,
             .getNotifications, .getUnreadNotificationCount, .getNotificationPreferences:
            return .get

        case .appleSignIn, .googleSignIn, .emailSignIn, .emailSignUp,
             .resendConfirmationEmail, .requestPasswordReset,
             .refreshToken, .logout,
             .saveProgram,
             .scheduleWorkout,
             .createWorkout, .recordSet, .addExtraSet, .swapExercise, .addAdHocSet,
             .createStandaloneSession, .recordStandaloneSet,
             .registerDevice,
             .createFeedback,
             .follow, .acceptFollowRequest,
             .uploadPostPhoto, .createPost,
             .block, .report,
             .markAllNotificationsRead:
            return .post

        case .activateProgram, .deactivateProgram, .completeProgram,
             .updateWorkoutNotes, .updateWorkoutDate, .completeWorkout, .updateSet,
             .updateStandaloneSet, .completeStandaloneSession,
             .completeCoreWorkout,
             .updateFeedback,
             .updateMe, .updatePost,
             .updateNotification, .updateNotificationPreferences:
            return .patch

        case .updateExerciseNotes, .saveCoreWorkout,
             .addReaction:
            return .put

        case .unsaveProgram, .unscheduleWorkout,
             .abandonWorkout, .deleteSet, .deleteExtraSet, .deleteCoreWorkout,
             .deleteStandaloneSet, .abandonStandaloneSession,
             .unregisterDevice, .deleteAccount,
             .unfollow, .removeFollower, .deleteFollowRequest,
             .deletePost, .removeReaction, .unblock:
            return .delete
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .appleSignIn(let b): return b
        case .googleSignIn(let b): return b
        case .emailSignIn(let b): return b
        case .emailSignUp(let b): return b
        case .resendConfirmationEmail(let b): return b
        case .requestPasswordReset(let b): return b
        case .refreshToken(let b): return b
        case .logout(let b): return b
        case .updateMe(let b): return b
        case .saveProgram(let id): return SaveProgramBody(programId: id)
        case .scheduleWorkout(let b): return b
        case .createWorkout(let b): return b
        case .updateWorkoutNotes(_, let b): return b
        case .updateWorkoutDate(_, let b): return b
        case .completeWorkout(_, let b): return b
        case .recordSet(_, let b): return b
        case .updateSet(_, _, let b): return b
        case .addExtraSet(_, _, let b): return b
        case .swapExercise(_, _, let b): return b
        case .addAdHocSet(_, let b): return b
        case .saveCoreWorkout(_, let b): return b
        case .completeCoreWorkout(_, let b): return b
        case .createStandaloneSession(let b): return b
        case .recordStandaloneSet(_, let b): return b
        case .updateStandaloneSet(_, _, let b): return b
        case .completeStandaloneSession(_, let b): return b
        case .updateExerciseNotes(_, let b): return b
        case .registerDevice(let b): return b
        case .updateFeedback(_, let b): return b
        case .follow(let b): return b
        case .createPost(let b): return b
        case .updatePost(_, let b): return b
        case .block(let b): return b
        case .report(let b): return b
        case .updateNotification(_, let b): return b
        case .markAllNotificationsRead(let b): return b
        case .updateNotificationPreferences(let b): return b
        default: return nil
        }
    }

    /// Extra request headers beyond Content-Type and Authorization.
    var headers: [String: String] {
        switch self {
        // Selects the server's JSON (native) logout path instead of the web
        // cookie-clearing redirect.
        case .logout: return ["X-Client-Type": "native"]
        default: return [:]
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .getExercises(let search):
            guard let search, !search.isEmpty else { return nil }
            return [URLQueryItem(name: "search", value: search)]

        case .getScheduledWorkouts(let userProgramId, let from, let to):
            var items = [URLQueryItem(name: "userProgramId", value: userProgramId)]
            if let from {
                items.append(URLQueryItem(name: "from", value: APIEndpoint.iso8601String(from)))
            }
            if let to {
                items.append(URLQueryItem(name: "to", value: APIEndpoint.iso8601String(to)))
            }
            return items

        case .getDashboard(let timeZone):
            guard let timeZone else { return nil }
            return [URLQueryItem(name: "timeZone", value: timeZone)]

        case .getHistory(let type, let limit, let before, let beforeId):
            var items: [URLQueryItem] = []
            if let type {
                items.append(URLQueryItem(name: "type", value: type.rawValue))
            }
            if let limit, limit > 0 {
                items.append(URLQueryItem(name: "limit", value: String(limit)))
            }
            // The server requires the cursor pair together — sending `before`
            // without `beforeId` 400s ("before and beforeId must be provided
            // together"). Only emit the cursor when both are present.
            if let before, let beforeId {
                items.append(URLQueryItem(name: "before", value: APIEndpoint.iso8601String(before)))
                items.append(URLQueryItem(name: "beforeId", value: beforeId))
            }
            return items.isEmpty ? nil : items

        case .getStandaloneWorkouts(let category):
            guard let category, !category.isEmpty else { return nil }
            return [URLQueryItem(name: "category", value: category)]

        case .searchUsers(let query):
            return [URLQueryItem(name: "q", value: query)]

        case .checkUsernameAvailability(let username):
            return [URLQueryItem(name: "username", value: username)]

        case .getFollowRequests(let direction):
            return [URLQueryItem(name: "direction", value: direction.rawValue)]

        case .getFeed(let page), .getUserPosts(_, let page), .getReactors(_, _, let page):
            let items = page.queryItems
            return items.isEmpty ? nil : items

        case .getNotifications(let status, let page):
            return [URLQueryItem(name: "status", value: status.rawValue)] + page.queryItems

        default:
            return nil
        }
    }

    func urlRequest(baseURL: URL, accessToken: String?) throws -> URLRequest {
        let pathURL = baseURL.appending(path: path)
        let url: URL
        if let queryItems, !queryItems.isEmpty {
            guard var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false) else {
                throw URLError(.badURL)
            }
            components.queryItems = queryItems
            guard let composed = components.url else { throw URLError(.badURL) }
            url = composed
        } else {
            url = pathURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let body {
            request.httpBody = try JSONCoding.encoder.encode(body)
        }
        return request
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func iso8601String(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }
}

// MARK: - Query Types

/// `?type=` filter for GET /api/history. Lowercase on the wire, per the
/// endpoint contract (unlike the uppercase response-side enums).
nonisolated enum HistoryTypeFilter: String, Sendable {
    case program
    case standalone
}

// MARK: - Request Body Types
// All body structs are nonisolated so their Encodable conformance can be used
// from any actor context (e.g., URLSession data tasks dispatched from non-MainActor code).

nonisolated struct AppleSignInBody: Encodable, Sendable {
    let identityToken: String
    let fullName: FullName?

    struct FullName: Encodable, Sendable {
        let givenName: String?
        let familyName: String?
    }
}

nonisolated struct GoogleSignInBody: Encodable, Sendable {
    let idToken: String
}

nonisolated struct EmailSignInBody: Encodable, Sendable {
    let email: String
    let password: String
}

nonisolated struct EmailSignUpBody: Encodable, Sendable {
    let email: String
    let password: String
    let name: String?
}

nonisolated struct ResendConfirmationBody: Encodable, Sendable {
    let email: String
}

nonisolated struct PasswordResetBody: Encodable, Sendable {
    let email: String
}

nonisolated struct RefreshTokenBody: Encodable, Sendable {
    let refreshToken: String
}

nonisolated struct SaveProgramBody: Encodable, Sendable {
    let programId: String
}

nonisolated struct ScheduleWorkoutBody: Encodable, Sendable {
    let userProgramId: String
    let weekNumber: Int
    let dayNumber: Int
    /// Sent as `"yyyy-MM-dd"`, the local day the user picked.
    let scheduledDate: CalendarDay
}

/// POST /api/workouts. Send `nil` for current-position; provide week/day for retroactive.
nonisolated struct CreateWorkoutBody: Encodable, Sendable {
    let weekNumber: Int
    let dayNumber: Int
}

nonisolated struct UpdateWorkoutNotesBody: Encodable, Sendable {
    let notes: String
}

/// PATCH /api/workouts/:id with `{ completedAt }`. Sent as-is, no `notes`
/// field — keeping the body shape narrow means the server's `'notes' in body`
/// check correctly leaves notes untouched.
nonisolated struct UpdateWorkoutDateBody: Encodable, Sendable {
    let completedAt: Date
}

/// PATCH /api/workouts/[id]/complete. `completedAt: nil` means "now" on the server.
nonisolated struct CompleteWorkoutBody: Encodable, Sendable {
    let completedAt: Date?
}

nonisolated struct RecordSetBody: Encodable, Sendable {
    let exerciseSetId: String
    let reps: Int?
    let weight: Double?
    let rpe: Double?
    let notes: String?
}

nonisolated struct UpdateSetBody: Encodable, Sendable {
    let reps: Int?
    let weight: Double?
    let rpe: Double?
    let notes: String?
}

nonisolated struct AddExtraSetBody: Encodable, Sendable {
    let reps: Int?
    let weight: Double?
    let rpe: Double?
    let notes: String?
}

nonisolated struct SwapExerciseBody: Encodable, Sendable {
    let replacementExerciseId: String
}

nonisolated struct AddAdHocSetBody: Encodable, Sendable {
    let exerciseName: String
}

/// PUT /api/workouts/:sessionId/core-workout. `exerciseIds` is ordered (array
/// index → 1-based order); the server sets sets = array length. Saving replaces
/// any existing circuit and resets completion.
nonisolated struct SaveCoreWorkoutBody: Encodable, Sendable {
    let timeSeconds: Int
    let restSeconds: Int
    let exerciseIds: [String]
}

/// PATCH /api/workouts/:sessionId/core-workout/complete. Sent only when we have
/// an explicit timestamp; a nil body lets the server default to "now".
nonisolated struct CompleteCoreWorkoutBody: Encodable, Sendable {
    let completedAt: Date
}

/// POST /api/standalone-workout-sessions.
nonisolated struct CreateStandaloneSessionBody: Encodable, Sendable {
    let standaloneWorkoutId: String
}

/// POST /api/standalone-workout-sessions/:id/sets. The server requires
/// **exactly one** of `standaloneWorkoutSetId` / `adhocExerciseName`; nil
/// optionals are omitted from the encoded JSON, so use the factory methods to
/// keep the invariant instead of the memberwise init.
nonisolated struct RecordStandaloneSetBody: Encodable, Sendable {
    let standaloneWorkoutSetId: String?
    let adhocExerciseName: String?
    let reps: Int?
    let weight: Double?
    let rpe: Double?
    let notes: String?

    // Private so callers can't hand-build a body with both or neither
    // discriminator — the factories below are the only way in.
    private init(
        standaloneWorkoutSetId: String?, adhocExerciseName: String?,
        reps: Int?, weight: Double?, rpe: Double?, notes: String?
    ) {
        self.standaloneWorkoutSetId = standaloneWorkoutSetId
        self.adhocExerciseName = adhocExerciseName
        self.reps = reps
        self.weight = weight
        self.rpe = rpe
        self.notes = notes
    }

    static func prescribed(
        standaloneWorkoutSetId: String,
        reps: Int?, weight: Double?, rpe: Double?, notes: String?
    ) -> RecordStandaloneSetBody {
        RecordStandaloneSetBody(
            standaloneWorkoutSetId: standaloneWorkoutSetId, adhocExerciseName: nil,
            reps: reps, weight: weight, rpe: rpe, notes: notes
        )
    }

    static func adhoc(
        exerciseName: String,
        reps: Int?, weight: Double?, rpe: Double?, notes: String?
    ) -> RecordStandaloneSetBody {
        RecordStandaloneSetBody(
            standaloneWorkoutSetId: nil, adhocExerciseName: exerciseName,
            reps: reps, weight: weight, rpe: rpe, notes: notes
        )
    }
}

nonisolated struct UpdateExerciseNotesBody: Encodable, Sendable {
    let notes: String
}

/// POST /api/devices/register. `token` is the APNs token as lowercase hex;
/// `environment` is the signed build's APNs environment (`PushEnvironment`).
nonisolated struct DeviceRegistrationBody: Encodable, Sendable {
    let token: String
    let platform: String
    let environment: String
}

/// POST /api/auth/logout (native). `deviceToken` is sent only on a
/// user-initiated sign-out, alongside the refresh token that proves who is
/// signing out; nil keys are omitted from the JSON.
nonisolated struct LogoutBody: Encodable, Sendable, Equatable {
    let refreshToken: String
    let deviceToken: String?
}

/// PATCH /api/auth/me. Send any subset; nil fields are omitted. To clear the
/// bio send `""` (the server treats `""` and `null` the same).
nonisolated struct UpdateMeBody: Encodable, Sendable, Equatable {
    var profileVisibility: ProfileVisibility?
    var username: String?
    var bio: String?
    var showActiveProgram: Bool?
    var showWorkoutCount: Bool?
    var weeklyWorkoutGoalEnabled: Bool?
    /// 1–7. Setting it leaves `weeklyWorkoutGoalEnabled` alone.
    var weeklyWorkoutGoal: Int?
    var weekStartDay: WeekStartDay?
}

/// POST /api/following.
nonisolated struct FollowBody: Encodable, Sendable, Equatable {
    let userId: String
}

/// POST /api/posts. A workout share names **one** of `workoutSessionId`
/// (a `PROGRAM` history row) or `standaloneSessionId` (a `STANDALONE` row) —
/// never both — so build it through `init(body:photoIds:sharing:)`.
nonisolated struct CreatePostBody: Encodable, Sendable, Equatable {
    let body: String?
    let photoIds: [String]?
    let workoutSessionId: String?
    let standaloneSessionId: String?

    enum SharedWorkout: Sendable, Equatable {
        case program(sessionId: String)
        case standalone(sessionId: String)
    }

    init(body: String?, photoIds: [String] = [], sharing workout: SharedWorkout? = nil) {
        let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.body = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.photoIds = photoIds.isEmpty ? nil : photoIds
        switch workout {
        case .program(let id):
            workoutSessionId = id
            standaloneSessionId = nil
        case .standalone(let id):
            workoutSessionId = nil
            standaloneSessionId = id
        case nil:
            workoutSessionId = nil
            standaloneSessionId = nil
        }
    }
}

/// PATCH /api/posts/:id. Only the text can change.
nonisolated struct UpdatePostBody: Encodable, Sendable, Equatable {
    let body: String
}

/// POST /api/blocks.
nonisolated struct BlockBody: Encodable, Sendable, Equatable {
    let userId: String
}

/// POST /api/reports. Exactly one of `postId` / `userId`; build it with
/// `.post(...)` or `.user(...)`.
nonisolated struct ReportBody: Encodable, Sendable, Equatable {
    let postId: String?
    let userId: String?
    let reason: ReportReason
    let details: String?

    private init(postId: String?, userId: String?, reason: ReportReason, details: String?) {
        self.postId = postId
        self.userId = userId
        self.reason = reason
        let trimmed = details?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.details = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    static func post(_ postId: String, reason: ReportReason, details: String?) -> ReportBody {
        ReportBody(postId: postId, userId: nil, reason: reason, details: details)
    }

    static func user(_ userId: String, reason: ReportReason, details: String?) -> ReportBody {
        ReportBody(postId: nil, userId: userId, reason: reason, details: details)
    }
}

/// `?status=` for GET /api/notifications.
nonisolated enum NotificationListFilter: String, Sendable {
    case unread
    case all
}

/// PATCH /api/notifications/:id.
nonisolated struct UpdateNotificationBody: Encodable, Sendable, Equatable {
    let status: NotificationStatus
}

/// POST /api/notifications/read-all. `before` is the `createdAt` of the
/// newest item on screen, sent back exactly as received.
nonisolated struct MarkAllReadBody: Encodable, Sendable, Equatable {
    let before: String?
}

/// PATCH /api/notifications/preferences. Any subset; nil fields are omitted.
/// `timezone` must be an IANA name (`TimeZone.current.identifier`), never an
/// offset.
nonisolated struct UpdateNotificationPreferencesBody: Encodable, Sendable, Equatable {
    var push: [String: Bool]?
    var timezone: String?
    var workoutReminderTime: String?
    var workoutReminderDay: WorkoutReminderDay?
}
