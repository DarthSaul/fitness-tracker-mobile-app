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

    // User Programs
    case getUserPrograms
    case getActiveUserProgram
    case enrollInProgram(programId: String)

    // Workouts
    case getActiveWorkout
    case createWorkout(CreateWorkoutBody)
    case getWorkout(id: String)
    case completeWorkout(id: String)
    case recordSet(workoutId: String, body: RecordSetBody)

    // Exercises
    case getExercises

    // Analytics
    case getDashboard

    // Devices
    case registerDevice(DeviceRegistrationBody)
}

// MARK: - Request Building
extension APIEndpoint {
    var path: String {
        switch self {
        case .appleSignIn: return "/api/auth/native/apple"
        case .refreshToken: return "/api/auth/refresh"
        case .logout: return "/api/auth/logout"
        case .getPrograms: return "/api/programs"
        case .getProgram(let id): return "/api/programs/\(id)"
        case .getUserPrograms: return "/api/user-programs"
        case .getActiveUserProgram: return "/api/user-programs/active"
        case .enrollInProgram: return "/api/user-programs"
        case .getActiveWorkout: return "/api/workouts/active"
        case .createWorkout: return "/api/workouts"
        case .getWorkout(let id): return "/api/workouts/\(id)"
        case .completeWorkout(let id): return "/api/workouts/\(id)/complete"
        case .recordSet(let id, _): return "/api/workouts/\(id)/sets"
        case .getExercises: return "/api/exercises"
        case .getDashboard: return "/api/analytics/dashboard"
        case .registerDevice: return "/api/devices/register"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getPrograms, .getProgram, .getUserPrograms, .getActiveUserProgram,
             .getActiveWorkout, .getWorkout, .getExercises, .getDashboard:
            return .get
        case .appleSignIn, .refreshToken, .logout, .enrollInProgram,
             .createWorkout, .recordSet, .registerDevice:
            return .post
        case .completeWorkout:
            return .patch
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .appleSignIn(let b): return b
        case .refreshToken(let b): return b
        case .enrollInProgram(let id): return EnrollBody(programId: id)
        case .createWorkout(let b): return b
        case .recordSet(_, let b): return b
        case .registerDevice(let b): return b
        default: return nil
        }
    }

    func urlRequest(baseURL: URL, accessToken: String?) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
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
}

// MARK: - Request Body Types
// All DTOs are nonisolated so their Encodable conformance can be used from any
// actor context (e.g., URLSession data tasks dispatched from non-MainActor code).
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

nonisolated struct EnrollBody: Encodable, Sendable {
    let programId: String
}

nonisolated struct CreateWorkoutBody: Encodable, Sendable {
    let userProgramId: String
    let weekNumber: Int
    let dayNumber: Int
}

nonisolated struct RecordSetBody: Encodable, Sendable {
    let exerciseSetId: String
    let reps: Int
    let weight: Double?
    let rpe: Double?
    let notes: String?
}

nonisolated struct DeviceRegistrationBody: Encodable, Sendable {
    let token: String
    let platform: String
    let environment: String
}
