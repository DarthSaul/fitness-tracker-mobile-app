import SwiftUI

/// The Friends tab root (design-spec 01, and 11 when empty): title row with
/// People and Activity buttons, the follow-requests shortcut, the composer
/// row, then the feed. The hosting tab provides the NavigationStack.
struct FriendsView: View {
    @State private var viewModel: FeedViewModel
    @State private var compose: ComposeRequest?
    private let context: SocialContext

    /// How the New Post sheet opens: empty, or with the photo picker up.
    struct ComposeRequest: Identifiable {
        let id = UUID()
        let startWithPhotoPicker: Bool
    }

    init(context: SocialContext) {
        self.context = context
        _viewModel = State(initialValue: FeedViewModel(context: context))
    }

    var body: some View {
        FriendsFeedContent(viewModel: viewModel, compose: $compose)
            .postInteractionHost(context: context)
            .sheet(item: $compose) { request in
                ComposeSheet(context: context, startWithPhotoPicker: request.startWithPhotoPicker)
            }
    }
}

private struct FriendsFeedContent: View {
    let viewModel: FeedViewModel
    @Binding var compose: FriendsView.ComposeRequest?

    @Environment(SocialContext.self) private var context
    @Environment(NotificationCenterModel.self) private var notifications
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                // Requests and the composer show whether or not the feed is
                // empty: a new user may have requests waiting, and can post
                // a first update straight away.
                if !viewModel.incomingRequests.isEmpty {
                    FollowRequestsSummaryRow(
                        requests: viewModel.incomingRequests,
                        summary: viewModel.requestsSummary
                    )
                    .padding(.top, 14)
                }
                composerRow
                    .padding(.top, 12)
                Group {
                    if viewModel.isEmpty {
                        EmptyFeedCard()
                    } else {
                        feed
                    }
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, SocialStyle.screenInset)
            .padding(.bottom, 24)
        }
        .background(SocialStyle.background)
        .scrollingTitleChrome(title: "Friends")
        .navigationTitle("Friends")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded()
            await notifications.refreshUnreadCount()
        }
        .refreshable {
            await viewModel.refresh()
            await notifications.refreshUnreadCount()
        }
        // Signed photo URLs last 15 minutes; refetch rather than show broken
        // images when the user comes back to the app or the tab.
        .onAppear { Task { await viewModel.refreshIfPhotosExpired() } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await viewModel.refreshIfPhotosExpired()
                await notifications.refreshUnreadCount()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Friends")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                NavigationLink(value: FriendsRoute.people) {
                    CircleIconLabel(systemImage: "person.2.fill")
                }
                .accessibilityLabel("People")
                NavigationLink(value: FriendsRoute.activity) {
                    CircleIconLabel(systemImage: "bell", badge: notifications.unreadCount)
                }
                .accessibilityLabel(notifications.unreadCount > 0 ? "Activity, \(notifications.unreadCount) unread" : "Activity")
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 52)
        .padding(.top, 14)
    }

    // MARK: Composer

    private var composerRow: some View {
        HStack(spacing: 10) {
            myAvatar
            Button {
                compose = .init(startWithPhotoPicker: false)
            } label: {
                Text("Share an update…")
                    .font(.system(size: 15))
                    .foregroundStyle(SocialStyle.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(SocialStyle.card, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New post")
            Button {
                compose = .init(startWithPhotoPicker: true)
            } label: {
                Image(systemName: "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
            }
            .accessibilityLabel("New photo post")
        }
    }

    @ViewBuilder
    private var myAvatar: some View {
        if let profile = sessionManager.userProfile {
            InitialsAvatar(
                seed: profile.id,
                name: profile.name,
                fallback: profile.username ?? profile.email,
                imageURL: profile.avatarUrl.flatMap(URL.init(string:)),
                size: 36
            )
        } else {
            Circle().fill(SocialStyle.card).frame(width: 36, height: 36)
        }
    }

    // MARK: Feed

    @ViewBuilder
    private var feed: some View {
        let feed = viewModel.feed
        if !feed.hasLoaded && feed.isLoading {
            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in PostSkeletonCard() }
            }
        } else if let error = feed.loadError, feed.items.isEmpty {
            RetryCard(message: APIFailure(error).message) { Task { await viewModel.refresh() } }
        } else {
            LazyVStack(spacing: 12) {
                if let error = feed.loadError {
                    // Keep what's on screen; offer a retry above it.
                    RetryCard(message: APIFailure(error).message) { Task { await viewModel.refresh() } }
                }
                ForEach(feed.items) { post in
                    PostCardView(post: post)
                        .onAppear { Task { await feed.loadMoreIfNeeded(currentItem: post) } }
                }
                if feed.isLoadingMore {
                    ProgressView().padding()
                } else if let error = feed.loadMoreError {
                    RetryCard(message: APIFailure(error).message) { Task { await feed.retryLoadMore() } }
                }
            }
        }
    }
}

/// A placeholder post card while the first page loads.
private struct PostSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 12)
                    RoundedRectangle(cornerRadius: 4).frame(width: 70, height: 10)
                }
            }
            RoundedRectangle(cornerRadius: 4).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).frame(width: 200, height: 12)
        }
        .foregroundStyle(SocialStyle.fill.opacity(0.6))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SocialStyle.card, in: RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous))
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// Empty feed (design-spec 11): hero image, copy, Find friends and Invite.
private struct EmptyFeedCard: View {
    @Environment(SocialContext.self) private var context

    /// The public site. There's no per-user profile page on the web yet, so
    /// Invite shares the app's site rather than a profile link.
    private static let inviteURL = URL(string: "https://drdumbbell.app")!

    /// Aspect-fill the hero into `box`, with the crop anchored ~28% from the
    /// top so Dr. Dumbbell and the lifter both stay in frame.
    static func heroCrop(in box: CGSize) -> (size: CGSize, offset: CGPoint) {
        let image = UIImage(named: "Login")?.size ?? box
        guard image.width > 0, image.height > 0 else { return (box, .zero) }
        let scale = max(box.width / image.width, box.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        let offset = CGPoint(
            x: -(size.width - box.width) / 2,
            y: -(size.height - box.height) * 0.28
        )
        return (size, offset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 330)
                .overlay {
                    GeometryReader { proxy in
                        let crop = Self.heroCrop(in: proxy.size)
                        Image("Login")
                            .resizable()
                            .frame(width: crop.size.width, height: crop.size.height)
                            .offset(x: crop.offset.x, y: crop.offset.y)
                    }
                }
                .clipped()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Tracking progress is better together!")
                    .font(.system(size: 22, weight: .bold))
                Text("Follow friends to see their posts, react, and cheer them on as they accomplish their goals.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                HStack(spacing: 10) {
                    Button {
                        context.router.open(.people)
                    } label: {
                        Label("Find friends", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.pill(.blue, height: 42, fullWidth: true))

                    ShareLink(item: Self.inviteURL, message: Text("Train with me on Dr. Dumbbell.")) {
                        Label("Invite", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.pill(.gray, height: 42))
                }
                .padding(.top, 10)
            }
            .padding(18)
        }
        .background(SocialStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous))
    }
}
