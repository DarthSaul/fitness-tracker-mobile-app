import SwiftUI

/// A user's profile: friend (09), private and not followed (10), or my own.
struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    private let context: SocialContext

    init(userId: String, context: SocialContext) {
        self.context = context
        _viewModel = State(initialValue: ProfileViewModel(userId: userId, context: context))
    }

    var body: some View {
        ProfileContent(viewModel: viewModel)
            .postInteractionHost(context: context)
    }
}

private struct ProfileContent: View {
    let viewModel: ProfileViewModel
    @Environment(SocialContext.self) private var context
    @Environment(PostInteractions.self) private var interactions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let profile = viewModel.profile {
                    header(profile)
                    if let program = profile.stats.activeProgramRow {
                        currentProgramCard(program)
                    }
                    if viewModel.postsAreLocked {
                        lockCard(profile)
                    } else {
                        postsSection
                    }
                } else if viewModel.isGone {
                    ContentUnavailableView(
                        "Account not available",
                        systemImage: "person.slash",
                        description: Text("This account doesn't exist or isn't available.")
                    )
                    .padding(.top, 60)
                } else if let error = viewModel.loadError {
                    RetryCard(message: error.message) { Task { await viewModel.load() } }
                        .padding(SocialStyle.screenInset)
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .padding(.bottom, 40)
        }
        .background(SocialStyle.background)
        .navigationTitle(viewModel.profile?.user.handle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let profile = viewModel.profile, !profile.relationship.isSelf {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            interactions.report = .user(profile.user)
                        } label: {
                            Label("Report \(profile.user.firstName)…", systemImage: "exclamationmark.bubble")
                        }
                        Button(role: .destructive) {
                            interactions.blockCandidate = profile.user
                        } label: {
                            Label("Block \(profile.user.firstName)", systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .task { if viewModel.profile == nil { await viewModel.load() } }
        .refreshable { await viewModel.load() }
        .onChange(of: viewModel.didBlock) { _, blocked in
            if blocked { dismiss() }
        }
    }

    // MARK: Header

    private func header(_ profile: UserProfileDTO) -> some View {
        VStack(spacing: 0) {
            UserAvatarView(user: profile.user, size: 88)
            Text(profile.user.displayName)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Text(profile.user.handle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.top, 8)
            }
            HStack(spacing: 28) {
                stat(profile.stats.workoutCountRow ?? "—", "Workouts")
                stat("\(profile.followerCount)", "Followers")
                stat("\(profile.followingCount)", "Following")
            }
            .padding(.top, 16)

            actionButtons(profile)
                .padding(.top, 16)
        }
        .padding(.horizontal, SocialStyle.screenInset)
        .padding(.top, 6)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actionButtons(_ profile: UserProfileDTO) -> some View {
        VStack(spacing: 10) {
            if profile.relationship.isSelf {
                NavigationLink {
                    EditProfileView(context: context)
                } label: {
                    Text("Edit profile")
                }
                .buttonStyle(.pill(.gray, height: 40, fullWidth: true))
            } else {
                FollowButton(
                    user: profile.user,
                    outgoing: Binding(get: { viewModel.outgoing }, set: { viewModel.outgoing = $0 }),
                    fullWidth: true,
                    height: 40
                )
                if profile.relationship.incomingRequestId != nil {
                    incomingRequestBanner(profile)
                }
            }
        }
    }

    private func incomingRequestBanner(_ profile: UserProfileDTO) -> some View {
        HStack(spacing: 10) {
            Text("\(profile.user.firstName) wants to follow you")
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Approve") { Task { await viewModel.respondToRequest(accept: true) } }
                .buttonStyle(.pill(.blue))
            Button {
                Task { await viewModel.respondToRequest(accept: false) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(SocialStyle.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decline")
        }
        .disabled(viewModel.isRespondingToRequest)
        .padding(12)
        .background(SocialStyle.card, in: RoundedRectangle(cornerRadius: SocialStyle.smallCardRadius, style: .continuous))
    }

    // MARK: Program

    /// The active program's name only: ADR 001 allows no position or
    /// progress.
    private func currentProgramCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Current program")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(name)
                .font(.system(size: 17, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(SocialStyle.card, in: RoundedRectangle(cornerRadius: SocialStyle.smallCardRadius, style: .continuous))
        .padding(.horizontal, SocialStyle.screenInset)
        .padding(.top, 18)
    }

    // MARK: Posts

    @ViewBuilder
    private var postsSection: some View {
        let posts = viewModel.posts
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderText("Posts")
                .padding(.leading, 2)
                .padding(.top, 22)
            if !posts.hasLoaded && posts.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
            } else if let error = posts.loadError, posts.items.isEmpty {
                RetryCard(message: APIFailure(error).message) { Task { await posts.refresh() } }
            } else if posts.hasLoaded && posts.items.isEmpty {
                Text(viewModel.isSelf ? "You haven't posted yet." : "No posts yet.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(posts.items) { post in
                        PostCardView(post: post)
                            .onAppear { Task { await posts.loadMoreIfNeeded(currentItem: post) } }
                    }
                    if posts.isLoadingMore {
                        ProgressView().padding()
                    } else if let error = posts.loadMoreError {
                        RetryCard(message: APIFailure(error).message) { Task { await posts.retryLoadMore() } }
                    }
                }
            }
        }
        .padding(.horizontal, SocialStyle.screenInset)
    }

    // MARK: Lock

    private func lockCard(_ profile: UserProfileDTO) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .overlay(Circle().stroke(Color.secondary, lineWidth: 2))
            Text("This account is private")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 6)
            Text(profile.relationship.outgoing == .requested
                 ? "Once \(profile.user.firstName) approves your request, you'll see their posts."
                 : "Follow \(profile.user.firstName) to see their posts. They'll need to approve your request.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(SocialStyle.card, in: RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous))
        .padding(.horizontal, SocialStyle.screenInset)
        .padding(.top, 28)
    }
}
