import Foundation
import Observation
import SwiftUI

// MARK: - Events

/// A change made on one screen that other screens holding the same post or
/// user must reflect (the feed, a profile's posts, the single-post screen).
enum SocialEvent {
    case postCreated(PostDTO)
    case postUpdated(PostDTO)
    case postDeleted(id: String)
    /// Drop this user's content from every cached list immediately.
    case userBlocked(userId: String)
    /// Follows, followers or requests changed; counts and buttons may be stale.
    case followsChanged
}

/// A tiny in-process event bus. Subscribers are held weakly, so a view model
/// that goes away simply stops receiving events.
@MainActor
final class SocialEvents {
    private struct Subscription {
        weak var owner: AnyObject?
        let handler: (SocialEvent) -> Void
    }

    private var subscriptions: [Subscription] = []

    func subscribe(_ owner: AnyObject, handler: @escaping (SocialEvent) -> Void) {
        subscriptions.removeAll { $0.owner == nil || $0.owner === owner }
        subscriptions.append(Subscription(owner: owner, handler: handler))
    }

    func send(_ event: SocialEvent) {
        subscriptions.removeAll { $0.owner == nil }
        for subscription in subscriptions {
            subscription.handler(event)
        }
    }
}

// MARK: - Toasts

/// Transient messages for failures of optimistic actions (a reaction or
/// follow that rolled back). Shown by `ToastOverlay` at the root.
@Observable
@MainActor
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String) {
        let toast = Toast(message: message)
        current = toast
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self?.current?.id == toast.id else { return }
            self?.current = nil
        }
    }

    func dismiss() {
        current = nil
    }
}

// MARK: - Navigation

/// Destinations inside the Friends tab's NavigationStack.
nonisolated enum FriendsRoute: Hashable {
    case people
    case activity
    case requests
    case profile(userId: String)
    case post(id: String)
}

/// The Friends tab's navigation path, owned outside the view so a push tap
/// (or Home) can open a profile, a post or Activity.
@Observable
@MainActor
final class FriendsRouter {
    var path: [FriendsRoute] = []

    func open(_ route: FriendsRoute) {
        path.append(route)
    }

    /// Replaces the stack with `routes` (used by push deep links).
    func show(_ routes: [FriendsRoute]) {
        path = routes
    }
}

// MARK: - Context

/// The shared social services, injected once from `RootTabView` with
/// `.environment(...)` so every social screen builds its view models from the
/// same repository, event bus and toast center.
@Observable
@MainActor
final class SocialContext {
    let repository: SocialRepository
    let events = SocialEvents()
    let toasts = ToastCenter()
    let router = FriendsRouter()
    let sessionManager: SessionManager
    /// Reaction toggles and post deletion, shared so in-flight state is too.
    @ObservationIgnored private(set) var postActions: PostActions!

    init(repository: SocialRepository, sessionManager: SessionManager) {
        self.repository = repository
        self.sessionManager = sessionManager
        self.postActions = PostActions(context: self)
    }

    var currentUserId: String? { sessionManager.currentUserId }

    /// The forced sign-out every `.unauthorized` path runs.
    func handleUnauthorized() async {
        await sessionManager.signOut()
    }

    /// Classifies a failure; signs out on `.unauthorized` and returns nil,
    /// otherwise returns the failure for the caller to present.
    func failure(from error: any Error) async -> APIFailure? {
        let failure = APIFailure(error)
        if failure == .unauthorized {
            await handleUnauthorized()
            return nil
        }
        return failure
    }
}
