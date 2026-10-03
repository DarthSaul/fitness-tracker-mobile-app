import SwiftUI

/// People (design-spec 08): Find · Followers · Following.
struct PeopleView: View {
    @State private var viewModel: PeopleViewModel
    @State private var removeCandidate: FollowListUserDTO?

    init(context: SocialContext) {
        _viewModel = State(initialValue: PeopleViewModel(context: context))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                searchField
                SocialSegmentedControl(
                    segments: [
                        (.find, "Find"),
                        (.followers, viewModel.followersTitle),
                        (.following, viewModel.followingTitle),
                    ],
                    selection: $viewModel.tab
                )
                Group {
                    switch viewModel.tab {
                    case .find: findTab
                    case .followers: followersTab
                    case .following: followingTab
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, SocialStyle.screenInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SocialStyle.background)
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.large)
        .task { if !viewModel.listsLoaded { await viewModel.loadLists() } }
        .refreshable { await viewModel.loadLists() }
        .onChange(of: viewModel.query) { viewModel.queryChanged() }
        .onChange(of: viewModel.tab) { viewModel.queryChanged() }
        .confirmationAlert(
            "Remove \(removeCandidate?.user.displayName ?? "follower")?",
            isPresented: Binding(get: { removeCandidate != nil }, set: { if !$0 { removeCandidate = nil } }),
            message: "They won't be notified. They'll need to follow you again to see your posts.",
            confirmLabel: "Remove",
            confirmRole: .destructive
        ) {
            if let follower = removeCandidate {
                Task { await viewModel.removeFollower(follower) }
            }
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SocialStyle.tertiaryText)
            TextField(viewModel.tab == .find ? "Find by name or @username" : "Search", text: $viewModel.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(SocialStyle.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(SocialStyle.card, in: RoundedRectangle(cornerRadius: SocialStyle.fieldRadius, style: .continuous))
    }

    // MARK: Find

    @ViewBuilder
    private var findTab: some View {
        if viewModel.isSearching && viewModel.results.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
        } else if let error = viewModel.searchError {
            RetryCard(message: error.message) {
                if let normalized = SocialRules.normalizedSearchQuery(viewModel.query) {
                    Task { await viewModel.search(normalized) }
                }
            }
        } else if viewModel.searchedQuery == nil {
            hint("Search by name or @username. To find someone by email, type their whole address.")
        } else if viewModel.results.isEmpty {
            hint("No one found for “\(viewModel.query.trimmingCharacters(in: .whitespaces))”.")
        } else {
            SocialGroup {
                ForEach(viewModel.results) { row in
                    SocialRow(separatorInset: 72, showsSeparator: row.id != viewModel.results.last?.id) {
                        PersonRowLabel(
                            user: row.user,
                            subtitle: row.relationship.incoming == .following ? "\(row.user.handle) · Follows you" : row.user.handle
                        )
                        FollowButton(
                            user: row.user,
                            outgoing: Binding(
                                get: { row.relationship.outgoing },
                                set: { viewModel.setOutgoing($0, forResult: row.user.id) }
                            )
                        )
                    }
                }
            }
        }
    }

    // MARK: Followers

    @ViewBuilder
    private var followersTab: some View {
        if let content = listState {
            content
        } else if viewModel.followers.isEmpty {
            hint("No followers yet. When people follow you, they'll show up here.")
        } else {
            let rows = viewModel.filteredFollowers
            VStack(alignment: .leading, spacing: 0) {
                SocialGroup {
                    ForEach(rows) { follower in
                        SocialRow(separatorInset: 72, showsSeparator: follower.id != rows.last?.id) {
                            PersonRowLabel(user: follower.user, subtitle: viewModel.followerSubtitle(follower))
                            Button("Remove") { removeCandidate = follower }
                                .buttonStyle(.pill(.gray))
                                .disabled(viewModel.removingIds.contains(follower.id))
                        }
                    }
                }
                GroupFootnote(text: "Removed followers aren't notified. They'll need to follow you again to see your posts.")
            }
        }
    }

    // MARK: Following

    @ViewBuilder
    private var followingTab: some View {
        if let content = listState {
            content
        } else if viewModel.following.isEmpty {
            hint("You're not following anyone yet. Use Find to look people up.")
        } else {
            let rows = viewModel.filteredFollowing
            VStack(alignment: .leading, spacing: 0) {
                SocialGroup {
                    ForEach(rows) { followee in
                        SocialRow(separatorInset: 72, showsSeparator: followee.id != rows.last?.id) {
                            PersonRowLabel(user: followee.user, subtitle: viewModel.followingSubtitle(followee))
                            FollowButton(
                                user: followee.user,
                                outgoing: Binding(
                                    get: { viewModel.outgoing(for: followee.user.id) },
                                    set: { viewModel.setOutgoing($0, forFollowing: followee.user.id) }
                                )
                            )
                        }
                    }
                }
                GroupFootnote(text: "Tap Following to unfollow. You can follow or request again anytime.")
            }
        }
    }

    /// Loading or error for the two lists, or nil once loaded.
    private var listState: AnyView? {
        if let error = viewModel.listsError, !viewModel.listsLoaded {
            return AnyView(RetryCard(message: error.message) { Task { await viewModel.loadLists() } })
        }
        if !viewModel.listsLoaded {
            return AnyView(ProgressView().frame(maxWidth: .infinity).padding(.top, 24))
        }
        return nil
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 12)
    }
}

/// Avatar + name + subtitle, linking to the profile.
struct PersonRowLabel: View {
    let user: PublicUserDTO
    let subtitle: String

    var body: some View {
        NavigationLink(value: FriendsRoute.profile(userId: user.id)) {
            HStack(spacing: 12) {
                UserAvatarView(user: user, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
