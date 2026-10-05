import Foundation
import Observation

/// Who reacted to a post: one keyset-paged list per emoji
/// (`GET /api/posts/:id/reactions/:emoji`), plus "All", which merges the
/// loaded rows newest first.
@Observable
@MainActor
final class ReactorsViewModel {
    /// One who-reacted row, tagged with the emoji it's for (a person who
    /// used two emoji appears once under each, and twice under All).
    struct Row: Identifiable {
        let reactor: ReactorDTO
        let emoji: String
        var id: String { "\(emoji)|\(reactor.cursorId)" }
    }

    /// nil selects "All".
    var selectedEmoji: String?
    let summaries: [ReactionSummaryDTO]
    private(set) var lists: [String: KeysetPaginator<ReactorDTO>] = [:]

    init(post: PostDTO, initialEmoji: String?, context: SocialContext, pageSize: Int = 50) {
        summaries = Reactions.ordered(post.reactions)
        selectedEmoji = initialEmoji
        for summary in summaries {
            let emoji = summary.emoji
            lists[emoji] = KeysetPaginator(
                pageSize: pageSize,
                endRule: .shortPage,
                cursor: \.cursor,
                onUnauthorized: { await context.handleUnauthorized() },
                fetch: { try await context.repository.fetchReactors(postId: post.id, emoji: emoji, page: $0) }
            )
        }
    }

    var totalCount: Int { summaries.reduce(0) { $0 + $1.count } }

    var rows: [Row] {
        if let selectedEmoji {
            return (lists[selectedEmoji]?.items ?? []).map { Row(reactor: $0, emoji: selectedEmoji) }
        }
        return summaries
            .flatMap { summary in (lists[summary.emoji]?.items ?? []).map { Row(reactor: $0, emoji: summary.emoji) } }
            .sorted { $0.reactor.reactedAt.date > $1.reactor.reactedAt.date }
    }

    var isLoading: Bool {
        visibleLists.contains { !$0.hasLoaded && $0.isLoading }
    }

    var loadError: APIError? {
        visibleLists.compactMap(\.loadError).first
    }

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            for list in lists.values {
                group.addTask { await list.loadIfNeeded() }
            }
        }
    }

    func reload() async {
        await withTaskGroup(of: Void.self) { group in
            for list in visibleLists {
                group.addTask { await list.refresh() }
            }
        }
    }

    /// Called when the last row appears.
    func loadMore() async {
        for list in visibleLists where !list.reachedEnd {
            await list.loadMore()
        }
    }

    private var visibleLists: [KeysetPaginator<ReactorDTO>] {
        if let selectedEmoji { return lists[selectedEmoji].map { [$0] } ?? [] }
        return Array(lists.values)
    }
}
