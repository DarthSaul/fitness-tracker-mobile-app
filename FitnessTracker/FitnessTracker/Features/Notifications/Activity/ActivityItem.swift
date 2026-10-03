import Foundation

/// One Activity row: a notification, or several reactions to the same post
/// grouped into one ("Dev and 3 others reacted to your post").
nonisolated struct ActivityItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case reaction(postId: String, emoji: String?)
        case newFollower
        case followAccepted
        case workoutReminder
        case workoutUnfinished
    }

    let kind: Kind
    /// Every notification folded into this row (all dismissed together).
    let notifications: [NotificationItemDTO]
    /// Distinct actors, newest first.
    let actors: [PublicUserDTO]

    var id: String { notifications[0].id }
    var newest: NotificationItemDTO { notifications[0] }
    var createdAt: Date { newest.createdAt.date }
    var isUnread: Bool { notifications.contains { $0.status == .unread } }

    /// The bold lead (a person's name) and the rest of the sentence.
    var text: (name: String?, rest: String) {
        let lead = actors.first?.displayName
        switch kind {
        case .reaction(_, let emoji):
            if actors.count > 1 {
                let others = actors.count - 1
                return (lead, "and \(others) other\(others == 1 ? "" : "s") reacted to your post")
            }
            if let emoji { return (lead, "reacted \(emoji) to your post") }
            return (lead, "reacted to your post")
        case .newFollower:
            return (lead, "started following you")
        case .followAccepted:
            return (lead, "accepted your follow request")
        case .workoutReminder:
            let data = newest.data
            let day = data.day == "tomorrow" ? "tomorrow" : "today"
            var position = ""
            if let week = data.weekNumber, let dayNumber = data.dayNumber {
                position = " (Week \(week) · Day \(dayNumber))"
            }
            if let program = data.programName {
                return (nil, "Your \(program) workout\(position) is scheduled for \(day).")
            }
            return (nil, "You have a workout scheduled for \(day).")
        case .workoutUnfinished:
            return (nil, "You have an unfinished workout. Finish it so it counts.")
        }
    }

    var destination: NotificationDestination {
        NotificationDestination.for(type: newest.type, target: newest.target, actorId: actors.first?.id)
    }

    // MARK: - Building rows

    /// Turns a page of notifications into rows, newest first:
    /// - reactions are grouped by post, the row sitting where its newest
    ///   reaction is;
    /// - follow requests are left out (they live in Requests, reached from
    ///   the pinned row);
    /// - unknown types are hidden.
    static func build(from notifications: [NotificationItemDTO]) -> [ActivityItem] {
        var items: [ActivityItem] = []
        var reactionGroups: [String: Int] = [:]

        for notification in notifications {
            switch notification.type {
            case .postReaction:
                guard let postId = notification.target.postId else { continue }
                if let index = reactionGroups[postId] {
                    let existing = items[index]
                    var actors = existing.actors
                    if let actor = notification.actor, !actors.contains(where: { $0.id == actor.id }) {
                        actors.append(actor)
                    }
                    items[index] = ActivityItem(
                        kind: existing.kind,
                        notifications: existing.notifications + [notification],
                        actors: actors
                    )
                } else {
                    reactionGroups[postId] = items.count
                    items.append(ActivityItem(
                        kind: .reaction(postId: postId, emoji: notification.data.emoji),
                        notifications: [notification],
                        actors: notification.actor.map { [$0] } ?? []
                    ))
                }
            case .newFollower:
                items.append(single(notification, kind: .newFollower))
            case .followAccepted:
                items.append(single(notification, kind: .followAccepted))
            case .workoutReminder:
                items.append(single(notification, kind: .workoutReminder))
            case .workoutUnfinished:
                items.append(single(notification, kind: .workoutUnfinished))
            case .followRequest, .unknown:
                continue
            }
        }
        return items
    }

    private static func single(_ notification: NotificationItemDTO, kind: Kind) -> ActivityItem {
        ActivityItem(kind: kind, notifications: [notification], actors: notification.actor.map { [$0] } ?? [])
    }
}

/// "Today", "This week", "Earlier" sections, in that order, empty ones
/// dropped.
nonisolated enum ActivitySections {
    enum Section: String, CaseIterable {
        case today = "Today"
        case thisWeek = "This week"
        case earlier = "Earlier"
    }

    struct Group: Identifiable {
        let section: Section
        let items: [ActivityItem]
        var id: Section { section }
    }

    static func group(_ items: [ActivityItem], now: Date = .now, calendar: Calendar = .current) -> [Group] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        var buckets: [Section: [ActivityItem]] = [:]
        for item in items {
            let section: Section
            if item.createdAt >= startOfToday {
                section = .today
            } else if item.createdAt >= startOfWeek {
                section = .thisWeek
            } else {
                section = .earlier
            }
            buckets[section, default: []].append(item)
        }
        return Section.allCases.compactMap { section in
            buckets[section].map { Group(section: section, items: $0) }
        }
    }
}
