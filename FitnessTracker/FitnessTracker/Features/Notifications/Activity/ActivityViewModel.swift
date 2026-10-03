import Foundation
import Observation
import OSLog

/// Activity (design-spec 06): the notification inbox, paged (an empty page
/// is the end), with a pinned row for pending follow requests.
///
/// Opening the screen marks everything read and clears the bell badge, but
/// the rows keep their unread dots for this visit so the user can see what's
/// new. "Mark read" also clears the dots.
@Observable
@MainActor
final class ActivityViewModel {
    let inbox: KeysetPaginator<NotificationItemDTO>
    private(set) var incomingRequests: [FollowRequestDTO] = []
    /// Rows dismissed this visit (hidden immediately, restored on failure).
    private var dismissedIds: Set<String> = []

    private let context: SocialContext
    private let notifications: NotificationCenterModel

    init(context: SocialContext, notifications: NotificationCenterModel, pageSize: Int = 20) {
        self.context = context
        self.notifications = notifications
        let repository = notifications.repository
        self.inbox = KeysetPaginator(
            pageSize: pageSize,
            endRule: .emptyPage,
            cursor: \.cursor,
            onUnauthorized: { await context.handleUnauthorized() },
            fetch: { try await repository.fetch(status: .all, page: $0) }
        )
        context.events.subscribe(self) { [weak self] event in
            guard let self else { return }
            switch event {
            case .userBlocked(let userId):
                // The server removes every notification between the two of us.
                self.inbox.removeAll { $0.actor?.id == userId }
                self.incomingRequests.removeAll { $0.user.id == userId }
            case .followsChanged:
                Task { await self.loadRequests() }
            case .postDeleted(let id):
                self.inbox.removeAll { $0.target.postId == id }
            case .postCreated, .postUpdated:
                break
            }
        }
    }

    var items: [ActivityItem] {
        ActivityItem.build(from: inbox.items.filter { !dismissedIds.contains($0.id) })
    }

    var sections: [ActivitySections.Group] {
        ActivitySections.group(items)
    }

    var requestsSummary: String {
        FeedViewModel.namesSummary(incomingRequests.map(\.user.firstName))
    }

    // MARK: - Loading

    /// First load: fetch, then mark everything up to the newest item read.
    func open() async {
        async let page: Void = inbox.loadIfNeeded()
        async let requests: Void = loadRequests()
        _ = await (page, requests)
        await markAllReadOnServer()
    }

    func refresh() async {
        async let page: Void = inbox.refresh()
        async let requests: Void = loadRequests()
        _ = await (page, requests)
        await markAllReadOnServer()
    }

    func loadRequests() async {
        do {
            incomingRequests = try await context.repository.fetchFollowRequests(direction: .incoming)
        } catch {
            _ = await context.failure(from: error)
            Logger.data.error("Incoming requests failed: \(error)")
        }
    }

    // MARK: - Read state

    /// "Mark read": marks read on the server and clears the dots.
    func markAllRead() async {
        await markAllReadOnServer()
        for item in inbox.items where item.status == .unread {
            inbox.update(id: item.id) { $0.status = .read }
        }
    }

    /// `read-all` up to the newest `createdAt` on screen (raw, as received),
    /// so anything that arrives meanwhile stays unread.
    private func markAllReadOnServer() async {
        guard let newest = inbox.items.first else {
            notifications.setUnread(0)
            return
        }
        do {
            try await notifications.repository.markAllRead(before: newest.createdAt.raw)
            await notifications.refreshUnreadCount()
        } catch {
            _ = await context.failure(from: error)
            Logger.data.error("Mark all read failed: \(error)")
        }
    }

    /// Marks a tapped row read (optimistic).
    func markRead(_ item: ActivityItem) {
        let unread = item.notifications.filter { $0.status == .unread }
        guard !unread.isEmpty else { return }
        for notification in unread {
            inbox.update(id: notification.id) { $0.status = .read }
        }
        Task {
            for notification in unread {
                _ = try? await notifications.repository.setStatus(id: notification.id, .read)
            }
            await notifications.refreshUnreadCount()
        }
    }

    // MARK: - Dismiss

    /// Swipe to dismiss: hides the row (every notification grouped in it).
    func dismiss(_ item: ActivityItem) async {
        let ids = item.notifications.map(\.id)
        dismissedIds.formUnion(ids)
        do {
            for id in ids {
                _ = try await notifications.repository.setStatus(id: id, .dismissed)
            }
            for id in ids { inbox.remove(id: id) }
            dismissedIds.subtract(ids)
            await notifications.refreshUnreadCount()
        } catch {
            guard let failure = await context.failure(from: error) else { return }
            if failure == .notFound {
                for id in ids { inbox.remove(id: id) }
                dismissedIds.subtract(ids)
                return
            }
            dismissedIds.subtract(ids)
            context.toasts.show("Couldn't dismiss that. \(failure.message)")
        }
    }
}
