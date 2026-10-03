import Foundation
import Testing
@testable import FitnessTracker

@Suite("KeysetPaginator")
@MainActor
struct KeysetPaginatorTests {
    struct Row: Identifiable, Equatable {
        let id: String
        let createdAt: String
    }

    /// A fake server: newest-first rows, paged by an exact-string cursor.
    final class FakeServer {
        var rows: [Row]
        var queries: [PageQuery] = []
        var failNext: APIError?

        init(count: Int) {
            rows = (0..<count).map { i in
                Row(id: "id-\(String(format: "%03d", count - i))", createdAt: "2026-10-02T12:00:\(String(format: "%02d", 59 - i % 60)).\(String(format: "%03d", i))Z")
            }
        }

        func page(_ query: PageQuery) throws -> [Row] {
            queries.append(query)
            if let failNext {
                self.failNext = nil
                throw failNext
            }
            let start: Int
            if let cursor = query.cursor {
                guard let index = rows.firstIndex(where: { $0.id == cursor.beforeId && $0.createdAt == cursor.before }) else {
                    return []
                }
                start = index + 1
            } else {
                start = 0
            }
            return Array(rows[start..<min(start + (query.limit ?? 20), rows.count)])
        }
    }

    private func makePaginator(
        server: FakeServer,
        pageSize: Int = 3,
        endRule: PageEndRule = .shortPage,
        onUnauthorized: @escaping @MainActor () async -> Void = {}
    ) -> KeysetPaginator<Row> {
        KeysetPaginator(
            pageSize: pageSize,
            endRule: endRule,
            cursor: { PageCursor(before: $0.createdAt, beforeId: $0.id) },
            onUnauthorized: onUnauthorized,
            fetch: { try server.page($0) }
        )
    }

    @Test("pages forward with the last item's exact cursor, then stops on a short page")
    func pagesToEnd() async {
        let server = FakeServer(count: 7)
        let paginator = makePaginator(server: server)

        await paginator.refresh()
        #expect(paginator.items.count == 3)
        #expect(server.queries[0].cursor == nil)
        #expect(server.queries[0].limit == 3)

        await paginator.loadMore()
        #expect(paginator.items.count == 6)
        // Sent back byte-for-byte, milliseconds included.
        #expect(server.queries[1].cursor == PageCursor(before: server.rows[2].createdAt, beforeId: server.rows[2].id))
        #expect(!paginator.reachedEnd)

        await paginator.loadMore()
        #expect(paginator.items.count == 7)
        #expect(paginator.reachedEnd)

        await paginator.loadMore()
        #expect(server.queries.count == 3, "no request after the end")
        #expect(paginator.items.map(\.id) == server.rows.map(\.id))
    }

    @Test("a full final page needs one more (short) page under the short-page rule")
    func exactMultipleOfPageSize() async {
        let server = FakeServer(count: 6)
        let paginator = makePaginator(server: server)
        await paginator.refresh()
        await paginator.loadMore()
        #expect(!paginator.reachedEnd)
        await paginator.loadMore()
        #expect(paginator.reachedEnd)
        #expect(paginator.items.count == 6)
    }

    @Test("notifications end only on an empty page")
    func emptyPageRule() async {
        let server = FakeServer(count: 4)
        let paginator = makePaginator(server: server, endRule: .emptyPage)
        await paginator.refresh()
        await paginator.loadMore()
        #expect(paginator.items.count == 4)
        #expect(!paginator.reachedEnd, "a short page isn't the end for notifications")
        await paginator.loadMore()
        #expect(paginator.reachedEnd)
    }

    @Test("refresh starts over from the top")
    func refreshResets() async {
        let server = FakeServer(count: 7)
        let paginator = makePaginator(server: server)
        await paginator.refresh()
        await paginator.loadMore()
        await paginator.refresh()
        #expect(paginator.items.count == 3)
        #expect(server.queries.last?.cursor == nil)
    }

    @Test("a failed loadMore isn't retried automatically")
    func noAutoRetryAfterFailure() async {
        let server = FakeServer(count: 7)
        let paginator = makePaginator(server: server)
        await paginator.refresh()

        server.failNext = .httpError(statusCode: 429, message: "Too many requests", data: Data())
        await paginator.loadMore()
        #expect(paginator.loadMoreError == .httpError(statusCode: 429, message: nil, data: Data()))
        let attempts = server.queries.count

        await paginator.loadMoreIfNeeded(currentItem: paginator.items[paginator.items.count - 1])
        #expect(server.queries.count == attempts, "row appearance must not retry a failure")

        await paginator.retryLoadMore()
        #expect(paginator.loadMoreError == nil)
        #expect(paginator.items.count == 6)
    }

    @Test("an unauthorized failure runs the sign-out hook")
    func unauthorizedCallsHook() async {
        let server = FakeServer(count: 3)
        server.failNext = .unauthorized
        var signedOut = false
        let paginator = makePaginator(server: server, onUnauthorized: { signedOut = true })
        await paginator.refresh()
        #expect(signedOut)
        #expect(paginator.loadError == nil)
    }

    @Test("local mutations insert, replace and remove by id")
    func mutations() async {
        let server = FakeServer(count: 3)
        let paginator = makePaginator(server: server)
        await paginator.refresh()

        paginator.insertAtTop(Row(id: "new", createdAt: "2026-10-03T00:00:00.000Z"))
        #expect(paginator.items.first?.id == "new")

        paginator.replace(Row(id: "new", createdAt: "changed"))
        #expect(paginator.items.first?.createdAt == "changed")

        paginator.remove(id: "new")
        #expect(paginator.items.count == 3)

        paginator.removeAll { $0.id.hasSuffix("3") }
        #expect(paginator.items.count == 2)
    }

    @Test("a page that repeats a locally inserted item doesn't duplicate it")
    func dedupesOnAppend() async {
        let server = FakeServer(count: 6)
        let paginator = makePaginator(server: server)
        await paginator.refresh()
        // Pretend the 4th row was inserted locally (e.g. just posted).
        paginator.insertAtTop(server.rows[3])
        await paginator.loadMore()
        #expect(paginator.items.filter { $0.id == server.rows[3].id }.count == 1)
    }
}
