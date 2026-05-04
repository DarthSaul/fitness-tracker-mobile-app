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
    case refreshToken(RefreshTokenBody)
    case logout

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

    // Scheduled Workouts
    case getScheduledWorkouts(userProgramId: String, from: Date?, to: Date?)
    case scheduleWorkout(ScheduleWorkoutBody)
    case unscheduleWorkout(id: String)

    // Workouts
    case getActiveWorkout
    case createWorkout(CreateWorkoutBody?)
    case getWorkout(id: String)
    case abandonWorkout(id: String)
    case updateWorkoutNotes(id: String, body: UpdateWorkoutNotesBody)
    case completeWorkout(id: String, body: CompleteWorkoutBody?)
    case recordSet(workoutId: String, body: RecordSetBody)
    case updateSet(workoutId: String, setId: String, body: UpdateSetBody)
    case deleteSet(workoutId: String, setId: String)
    case addExtraSet(workoutId: String, programExerciseId: String, body: AddExtraSetBody)
    case deleteExtraSet(workoutId: String, completedSetId: String)
    case swapExercise(workoutId: String, programExerciseId: String, body: SwapExerciseBody)
    case addAdHocSet(workoutId: String, body: AddAdHocSetBody)

    // Exercises
    case getExercises(search: String?)
    case getExerciseNotes(exerciseId: String)
    case updateExerciseNotes(exerciseId: String, body: UpdateExerciseNotesBody)

    // Analytics
    case getDashboard(tzOffsetMinutes: Int?)
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
}

// MARK: - Request Building
extension APIEndpoint {
    var path: String {
        switch self {
        // Auth
        case .appleSignIn: return "/api/auth/native/apple"
        case .refreshToken: return "/api/auth/refresh"
        case .logout: return "/api/auth/logout"

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

        // Scheduled Workouts
        case .getScheduledWorkouts: return "/api/scheduled-workouts"
        case .scheduleWorkout: return "/api/scheduled-workouts"
        case .unscheduleWorkout(let id): return "/api/scheduled-workouts/\(id)"

        // Workouts
        case .getActiveWorkout: return "/api/workouts/active"
        case .createWorkout: return "/api/workouts"
        case .getWorkout(let id): return "/api/workouts/\(id)"
        case .abandonWorkout(let id): return "/api/workouts/\(id)"
        case .updateWorkoutNotes(let id, _): return "/api/workouts/\(id)"
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

        // Exercises
        case .getExercises: return "/api/exercises"
        case .getExerciseNotes(let id): return "/api/exercises/\(id)/notes"
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
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getPrograms, .getProgram, .getProgramDay,
             .getUserPrograms, .getActiveUserProgram, .getActiveProgramSessions,
             .getScheduledWorkouts,
             .getActiveWorkout, .getWorkout,
             .getExercises, .getExerciseNotes,
             .getDashboard, .getAnalyticsExercises, .getAnalyticsExercise,
             .getFeedback:
            return .get

        case .appleSignIn, .refreshToken, .logout,
             .saveProgram,
             .scheduleWorkout,
             .createWorkout, .recordSet, .addExtraSet, .swapExercise, .addAdHocSet,
             .registerDevice,
             .createFeedback:
            return .post

        case .activateProgram, .deactivateProgram,
             .updateWorkoutNotes, .completeWorkout, .updateSet,
             .updateFeedback:
            return .patch

        case .updateExerciseNotes:
            return .put

        case .unsaveProgram, .unscheduleWorkout,
             .abandonWorkout, .deleteSet, .deleteExtraSet,
             .unregisterDevice:
            return .delete
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .appleSignIn(let b): return b
        case .refreshToken(let b): return b
        case .saveProgram(let id): return SaveProgramBody(programId: id)
        case .scheduleWorkout(let b): return b
        case .createWorkout(let b): return b
        case .updateWorkoutNotes(_, let b): return b
        case .completeWorkout(_, let b): return b
        case .recordSet(_, let b): return b
        case .updateSet(_, _, let b): return b
        case .addExtraSet(_, _, let b): return b
        case .swapExercise(_, _, let b): return b
        case .addAdHocSet(_, let b): return b
        case .updateExerciseNotes(_, let b): return b
        case .registerDevice(let b): return b
        case .updateFeedback(_, let b): return b
        default: return nil
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

        case .getDashboard(let tzOffsetMinutes):
            guard let tzOffsetMinutes else { return nil }
            return [URLQueryItem(name: "tzOffset", value: String(tzOffsetMinutes))]

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
    let scheduledDate: Date
}

/// POST /api/workouts. Send `nil` for current-position; provide week/day for retroactive.
nonisolated struct CreateWorkoutBody: Encodable, Sendable {
    let weekNumber: Int
    let dayNumber: Int
}

nonisolated struct UpdateWorkoutNotesBody: Encodable, Sendable {
    let notes: String
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

nonisolated struct UpdateExerciseNotesBody: Encodable, Sendable {
    let notes: String
}

nonisolated struct DeviceRegistrationBody: Encodable, Sendable {
    let token: String
    let platform: String
    let environment: String
}
