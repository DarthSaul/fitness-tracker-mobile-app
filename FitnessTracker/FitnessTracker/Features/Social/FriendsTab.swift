import SwiftUI

/// Friends tab: the feed and everything reached from it, on a navigation
/// path owned by `FriendsRouter` so push taps can open screens here.
struct FriendsTab: View {
    @Environment(SocialContext.self) private var context

    var body: some View {
        @Bindable var router = context.router
        NavigationStack(path: $router.path) {
            FriendsView(context: context)
                .friendsDestinations()
        }
    }
}
