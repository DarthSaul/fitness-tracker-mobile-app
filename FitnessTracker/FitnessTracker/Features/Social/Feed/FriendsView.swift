import SwiftUI

/// The Friends tab root: a header row (title + people and notifications
/// icons), the post composer, then the following feed, newest first.
/// The hosting tab provides the NavigationStack.
struct FriendsView: View {
    @State private var viewModel: FeedViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: FeedViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header
                PostComposerView(viewModel: viewModel)
                    .padding(.horizontal)
                feedContent
            }
            .padding(.vertical, 12)
        }
        .scrollingTitleChrome(title: "Friends")
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.feed.loadIfNeeded() }
        .refreshable { await viewModel.feed.refresh() }
        // Signed photo URLs last 15 minutes; refetch rather than show broken
        // images when the user comes back to the app or the tab.
        .onAppear { Task { await viewModel.refreshIfPhotosExpired() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refreshIfPhotosExpired() } }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Friends")
                .font(.largeTitle.bold())
            Spacer(minLength: 12)
            HStack(spacing: 20) {
                NavigationLink {
                    SocialPlaceholderView(
                        title: "Find People",
                        systemImage: "person.2",
                        message: "Search for people to follow — coming soon."
                    )
                } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("People")

                NavigationLink {
                    SocialPlaceholderView(
                        title: "Notifications",
                        systemImage: "bell",
                        message: "Follows, requests and reactions will show up here — coming soon."
                    )
                } label: {
                    Image(systemName: "bell")
                }
                .accessibilityLabel("Notifications")
            }
            .font(.title2)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Feed

    @ViewBuilder
    private var feedContent: some View {
        let feed = viewModel.feed
        if !feed.hasLoaded && feed.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if feed.items.isEmpty {
            if let error = feed.loadError {
                ContentUnavailableView {
                    Label("Couldn't load your feed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(APIFailure(error).message)
                } actions: {
                    Button("Try Again") { Task { await feed.refresh() } }
                }
            } else if feed.hasLoaded {
                ContentUnavailableView(
                    "Your feed is empty",
                    systemImage: "person.2",
                    description: Text("Posts from you and the people you follow show up here. Tap the people icon to find friends.")
                )
            }
        } else {
            ForEach(feed.items) { post in
                PostCellView(post: post)
                    .padding(.horizontal)
                    .onAppear {
                        Task { await feed.loadMoreIfNeeded(currentItem: post) }
                    }
            }
            feedFooter
        }
    }

    @ViewBuilder
    private var feedFooter: some View {
        let feed = viewModel.feed
        if feed.isLoadingMore {
            ProgressView().frame(maxWidth: .infinity).padding()
        } else if let error = feed.loadMoreError {
            VStack(spacing: 8) {
                Text(APIFailure(error).message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await feed.retryLoadMore() } }
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

/// Stand-in destination for the header icons until people search and the
/// notifications inbox are built.
struct SocialPlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
