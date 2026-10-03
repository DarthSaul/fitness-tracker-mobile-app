import Foundation

// MARK: - Wire Timestamp

/// A timestamp that keeps the exact string the server sent alongside the
/// parsed `Date`. Use it for any field that doubles as a paging cursor
/// (`createdAt`, `reactedAt`): cursors are opaque and must go back to the
/// server byte-for-byte, never re-formatted from a `Date` (which would drop or
/// round the milliseconds and skip or repeat rows at a page boundary).
nonisolated struct WireTimestamp: Codable, Sendable, Hashable {
    let raw: String
    let date: Date

    init(raw: String, date: Date) {
        self.raw = raw
        self.date = date
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = JSONCoding.parseISO8601(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp, got '\(raw)'"
            )
        }
        self.raw = raw
        self.date = date
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

// MARK: - Cursor

/// The `before` + `beforeId` pair for the next page of a keyset-paged list,
/// taken from the **last** item of the previous page. The server requires
/// both together. Both values are opaque strings.
nonisolated struct PageCursor: Sendable, Equatable {
    let before: String
    let beforeId: String
}

/// `limit` + optional cursor for a keyset-paged GET. `limit` is clamped to
/// 1–50 server-side (default 20).
nonisolated struct PageQuery: Sendable, Equatable {
    var limit: Int?
    var cursor: PageCursor?

    static let firstPage = PageQuery(limit: nil, cursor: nil)

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let limit, limit > 0 {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let cursor {
            items.append(URLQueryItem(name: "before", value: cursor.before))
            items.append(URLQueryItem(name: "beforeId", value: cursor.beforeId))
        }
        return items
    }
}

/// How a keyset-paged list signals its end. The feed, a user's posts and the
/// who-reacted list end on a page shorter than `limit`; notifications end on
/// an empty page.
nonisolated enum PageEndRule: Sendable {
    case shortPage
    case emptyPage

    func isEnd(pageCount: Int, limit: Int) -> Bool {
        switch self {
        case .shortPage: return pageCount < limit
        case .emptyPage: return pageCount == 0
        }
    }
}

// MARK: - Paginator

/// One reusable driver for every keyset-paged list (feed, a user's posts,
/// who reacted, notifications). Owns the loaded items, the loading flags and
/// end detection; the caller supplies how to fetch a page and how to build a
/// cursor from an item.
///
/// - `refresh()` reloads from the top (pull-to-refresh). A refresh that
///   starts while an older request is in flight wins: the older result is
///   dropped rather than appended to the new list.
/// - `loadMore()` fetches the page after the last item. It never retries on
///   its own after a failure — a `429` must not turn into a request loop — so
///   the view offers `retryLoadMore()` instead.
/// - The mutation helpers keep optimistic edits (a new post, a deleted post,
///   a reaction toggle, a block) in one place.
@Observable
@MainActor
final class KeysetPaginator<Item: Identifiable> {
    typealias Fetch = @MainActor (_ query: PageQuery) async throws -> [Item]

    // MARK: State
    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var reachedEnd = false
    /// True once the first page has landed, so a view can tell "empty" from
    /// "not loaded yet".
    private(set) var hasLoaded = false
    /// The failure from the last `refresh()`, cleared when one starts.
    private(set) var loadError: APIError?
    /// The failure from the last `loadMore()`. While set, `loadMoreIfNeeded`
    /// does nothing until the user taps retry.
    private(set) var loadMoreError: APIError?

    // MARK: Configuration
    let pageSize: Int
    private let endRule: PageEndRule
    private let cursor: (Item) -> PageCursor
    private let fetch: Fetch
    /// Called when a request fails with `.unauthorized` (the refresh token is
    /// dead). Callers pass the app's forced sign-out.
    private let onUnauthorized: @MainActor () async -> Void

    /// Bumped by every refresh and reset, so a response that lands after a
    /// newer refresh began is discarded.
    private var generation = 0

    init(
        pageSize: Int = 20,
        endRule: PageEndRule = .shortPage,
        cursor: @escaping (Item) -> PageCursor,
        onUnauthorized: @escaping @MainActor () async -> Void = {},
        fetch: @escaping Fetch
    ) {
        self.pageSize = pageSize
        self.endRule = endRule
        self.cursor = cursor
        self.onUnauthorized = onUnauthorized
        self.fetch = fetch
    }

    // MARK: Loading

    func refresh() async {
        generation += 1
        let requestGeneration = generation
        isLoading = true
        loadError = nil
        loadMoreError = nil
        defer {
            if requestGeneration == generation { isLoading = false }
        }

        do {
            let page = try await fetch(PageQuery(limit: pageSize, cursor: nil))
            guard requestGeneration == generation else { return }
            items = page
            reachedEnd = endRule.isEnd(pageCount: page.count, limit: pageSize)
            hasLoaded = true
        } catch {
            guard requestGeneration == generation else { return }
            let apiError = Self.apiError(from: error)
            if apiError == .unauthorized {
                await onUnauthorized()
                return
            }
            loadError = apiError
        }
    }

    /// Loads the first page only if nothing has been loaded yet — for
    /// `.task {}` so returning to a screen doesn't refetch.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await refresh()
    }

    func loadMore() async {
        guard hasLoaded, !isLoading, !isLoadingMore, !reachedEnd, let last = items.last else { return }
        let requestGeneration = generation
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }

        do {
            let page = try await fetch(PageQuery(limit: pageSize, cursor: cursor(last)))
            guard requestGeneration == generation else { return }
            // Keyset paging doesn't repeat rows, but an item inserted locally
            // (a new post) could also arrive from the server; keep one copy.
            let existing = Set(items.map(\.id))
            items.append(contentsOf: page.filter { !existing.contains($0.id) })
            reachedEnd = endRule.isEnd(pageCount: page.count, limit: pageSize)
        } catch {
            guard requestGeneration == generation else { return }
            let apiError = Self.apiError(from: error)
            if apiError == .unauthorized {
                await onUnauthorized()
                return
            }
            loadMoreError = apiError
        }
    }

    /// Call from a row's `.onAppear`: loads the next page when the last row
    /// shows, unless the previous attempt failed.
    func loadMoreIfNeeded(currentItem item: Item) async {
        guard item.id == items.last?.id, loadMoreError == nil else { return }
        await loadMore()
    }

    func retryLoadMore() async {
        loadMoreError = nil
        await loadMore()
    }

    // MARK: Local mutations

    func insertAtTop(_ item: Item) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
    }

    func replace(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func update(id: Item.ID, _ transform: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        transform(&items[index])
    }

    func remove(id: Item.ID) {
        items.removeAll { $0.id == id }
    }

    func removeAll(where shouldRemove: (Item) -> Bool) {
        items.removeAll(where: shouldRemove)
    }

    /// Clears everything, e.g. when the list's owner changes.
    func reset() {
        generation += 1
        items = []
        isLoading = false
        isLoadingMore = false
        reachedEnd = false
        hasLoaded = false
        loadError = nil
        loadMoreError = nil
    }

    // MARK: Helpers

    private static func apiError(from error: any Error) -> APIError {
        (error as? APIError) ?? .unknown(error)
    }
}
