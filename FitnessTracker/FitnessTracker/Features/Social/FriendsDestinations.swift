import SwiftUI

/// Resolves a `FriendsRoute` to its screen. Registered on every
/// NavigationStack that shows social content (Friends, Settings → profile,
/// the who-reacted sheet) so profile and post links work everywhere.
private struct FriendsDestination: View {
    let route: FriendsRoute
    @Environment(SocialContext.self) private var context
    @Environment(NotificationCenterModel.self) private var notifications

    var body: some View {
        switch route {
        case .people:
            PeopleView(context: context)
        case .activity:
            ActivityView(context: context, notifications: notifications)
        case .requests:
            RequestsView(context: context)
        case .profile(let userId):
            ProfileView(userId: userId, context: context)
        case .post(let id):
            PostDetailView(postId: id, context: context)
        }
    }
}

extension View {
    func friendsDestinations() -> some View {
        navigationDestination(for: FriendsRoute.self) { route in
            FriendsDestination(route: route)
        }
    }
}
