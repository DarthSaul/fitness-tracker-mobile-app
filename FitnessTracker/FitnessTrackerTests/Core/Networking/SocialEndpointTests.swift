import Foundation
import Testing
@testable import FitnessTracker

@Suite("Social endpoint request building")
struct SocialEndpointTests {
    private let base = URL(string: "http://localhost:3000")!

    private func request(_ endpoint: APIEndpoint) throws -> URLRequest {
        try endpoint.urlRequest(baseURL: base, accessToken: "token")
    }

    @Test("the reaction emoji is percent-encoded exactly once in the path")
    func emojiPathEncoding() throws {
        let url = try request(.addReaction(postId: "p1", emoji: "👍")).url?.absoluteString
        #expect(url == "http://localhost:3000/api/posts/p1/reactions/%F0%9F%91%8D")

        let heart = try request(.removeReaction(postId: "p1", emoji: "❤️")).url?.absoluteString
        #expect(heart == "http://localhost:3000/api/posts/p1/reactions/%E2%9D%A4%EF%B8%8F")

        let family = try request(.getReactors(postId: "p1", emoji: "👨‍👩‍👧", page: .firstPage)).url?.absoluteString
        #expect(family == "http://localhost:3000/api/posts/p1/reactions/%F0%9F%91%A8%E2%80%8D%F0%9F%91%A9%E2%80%8D%F0%9F%91%A7")
    }

    @Test("reaction methods: PUT adds, DELETE removes, GET lists")
    func reactionMethods() throws {
        #expect(try request(.addReaction(postId: "p", emoji: "🔥")).httpMethod == "PUT")
        #expect(try request(.removeReaction(postId: "p", emoji: "🔥")).httpMethod == "DELETE")
        #expect(try request(.getReactors(postId: "p", emoji: "🔥", page: .firstPage)).httpMethod == "GET")
    }

    @Test("the paging cursor is sent as the raw strings, together")
    func cursorQueryItems() throws {
        let cursor = PageCursor(before: "2026-10-02T12:00:00.123Z", beforeId: "post-9")
        let url = try #require(try request(.getFeed(page: PageQuery(limit: 20, cursor: cursor))).url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "limit", value: "20")))
        #expect(items.contains(URLQueryItem(name: "before", value: "2026-10-02T12:00:00.123Z")))
        #expect(items.contains(URLQueryItem(name: "beforeId", value: "post-9")))

        let first = try #require(try request(.getFeed(page: .firstPage)).url)
        #expect(first.query == nil)
    }

    @Test("notifications send status plus the cursor")
    func notificationQuery() throws {
        let cursor = PageCursor(before: "2026-10-02T12:00:00.000Z", beforeId: "n-1")
        let url = try #require(try request(.getNotifications(status: .unread, page: PageQuery(limit: 20, cursor: cursor))).url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first == URLQueryItem(name: "status", value: "unread"))
        #expect(items.contains(URLQueryItem(name: "beforeId", value: "n-1")))
    }

    @Test("native logout sends X-Client-Type and both tokens")
    func logoutRequest() throws {
        let req = try request(.logout(LogoutBody(refreshToken: "rt", deviceToken: "abcd")))
        #expect(req.httpMethod == "POST")
        #expect(req.url?.path() == "/api/auth/logout")
        #expect(req.value(forHTTPHeaderField: "X-Client-Type") == "native")
        let body = try #require(req.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["refreshToken": "rt", "deviceToken": "abcd"])
    }

    @Test("logout without a device token omits the key")
    func logoutWithoutDeviceToken() throws {
        let body = try #require(try request(.logout(LogoutBody(refreshToken: "rt", deviceToken: nil))).httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["refreshToken": "rt"])
    }

    @Test("search, username check and follow-request direction are query items")
    func otherQueries() throws {
        let search = try #require(try request(.searchUsers(query: "@saul")).url)
        #expect(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "q", value: "@saul")])

        let requests = try #require(try request(.getFollowRequests(direction: .outgoing)).url)
        #expect(requests.query == "direction=outgoing")
    }
}
