import Foundation

/// The reaction rules the UI applies on top of the API, which accepts any
/// single emoji (up to 10 distinct per user per post).
nonisolated enum Reactions {
    /// The fixed set the app offers, in display order.
    static let quick: [String] = ["💪", "🔥", "🏆", "👏", "😤"]

    /// Chips to show: the fixed set first, in fixed order, then any other
    /// emoji on the post (added from another client) in the server's order.
    /// Only emoji with a count above zero.
    static func ordered(_ reactions: [ReactionSummaryDTO]) -> [ReactionSummaryDTO] {
        let visible = reactions.filter { $0.count > 0 }
        let fixed = quick.compactMap { emoji in visible.first { $0.emoji == emoji } }
        let others = visible.filter { !quick.contains($0.emoji) }
        return fixed + others
    }

    /// The optimistic result of toggling my `emoji` on a post: adds 1 and
    /// marks it mine, or removes 1 and unmarks it (dropping a chip at zero).
    static func toggling(_ emoji: String, in reactions: [ReactionSummaryDTO]) -> [ReactionSummaryDTO] {
        var result = reactions
        if let index = result.firstIndex(where: { $0.emoji == emoji }) {
            if result[index].mine {
                result[index].count -= 1
                result[index].mine = false
                if result[index].count <= 0 { result.remove(at: index) }
            } else {
                result[index].count += 1
                result[index].mine = true
            }
        } else {
            result.append(ReactionSummaryDTO(emoji: emoji, count: 1, mine: true))
        }
        return result
    }

    static func isMine(_ emoji: String, in reactions: [ReactionSummaryDTO]) -> Bool {
        reactions.contains { $0.emoji == emoji && $0.mine }
    }

    /// The post's most-used reaction, for compact summaries.
    static func top(_ reactions: [ReactionSummaryDTO]) -> ReactionSummaryDTO? {
        reactions.max { $0.count < $1.count }
    }
}
