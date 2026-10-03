import Foundation
import Testing
@testable import FitnessTracker

@Suite("APIFailure status mapping")
struct APIFailureTests {
    private func http(_ status: Int, message: String? = nil, body: String = "") -> APIError {
        .httpError(statusCode: status, message: message, data: Data(body.utf8))
    }

    @Test("403 with profile_private is the lock state")
    func profilePrivate() {
        let body = #"{"statusCode":403,"statusMessage":"This profile is private","data":{"code":"profile_private"}}"#
        #expect(APIFailure(http(403, body: body)) == .profilePrivate)
        // A 403 without the code isn't the lock state.
        #expect(APIFailure(http(403)) == .other(message: nil))
    }

    @Test("status codes map to the cases the UI branches on")
    func statusCodes() {
        #expect(APIFailure(http(404)) == .notFound)
        #expect(APIFailure(http(409, message: "Workout already shared")) == .conflict(message: "Workout already shared"))
        #expect(APIFailure(http(413)) == .payloadTooLarge)
        #expect(APIFailure(http(415)) == .unsupportedMediaType)
        #expect(APIFailure(http(429)) == .rateLimited)
        #expect(APIFailure(http(400, message: "Invalid limit")) == .invalid(message: "Invalid limit"))
        #expect(APIFailure(APIError.unauthorized) == .unauthorized)
        #expect(APIFailure(APIError.network(URLError(.notConnectedToInternet))) == .offline)
    }

    @Test("409 reasons get specific copy")
    func conflictCopy() {
        #expect(APIFailure.conflict(message: "Workout already shared").message == "You've already shared this workout.")
        #expect(APIFailure.conflict(message: "Workout is not completed").message == "Only completed workouts can be shared.")
        #expect(APIFailure.conflict(message: "Username taken").message == "That username is taken.")
        #expect(APIFailure.conflict(message: "At most 10 different reactions per post").message
            == "You can add up to 10 different reactions to a post.")
    }

    @Test("429 says try again later")
    func rateLimitedCopy() {
        #expect(APIFailure.rateLimited.message.contains("Try again later"))
    }
}
