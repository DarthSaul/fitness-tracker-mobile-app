import SwiftUI

/// Home's FRIENDS section (replaces the old HISTORY preview; History lives in
/// Progress now). "See all" and each row open the Friends tab.
struct HomeFriendsSection: View {
    let viewModel: HomeFriendsViewModel
    @Environment(TabSelection.self) private var tabSelection
    @Environment(SocialContext.self) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeaderText("Friends")
                Spacer()
                Button("See all") { open([]) }
                    .font(.system(size: 15))
            }
            .padding(.horizontal, 2)

            card
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var card: some View {
        if !viewModel.hasLoaded {
            if viewModel.loadError != nil {
                row(showsSeparator: false) {
                    Text("Couldn't load friends' posts.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { Task { await viewModel.load() } }
                        .font(.system(size: 15))
                }
                .background(SocialStyle.card, in: cardShape)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(SocialStyle.card, in: cardShape)
            }
        } else if viewModel.posts.isEmpty {
            Button {
                open([.people])
            } label: {
                row(showsSeparator: false) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 17))
                    Text("Find friends to follow")
                        .font(.system(size: 15))
                    Spacer()
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .background(SocialStyle.card, in: cardShape)
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.posts) { post in
                    Button {
                        open([.post(id: post.id)])
                    } label: {
                        postRow(post, showsSeparator: post.id != viewModel.posts.last?.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(SocialStyle.card, in: cardShape)
            .clipShape(cardShape)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous)
    }

    private func postRow(_ post: PostDTO, showsSeparator: Bool) -> some View {
        row(showsSeparator: showsSeparator) {
            UserAvatarView(user: post.author, size: 36)
            (Text(post.author.firstName).fontWeight(.semibold)
                + Text(" \(HomeFriendSummary.text(for: post)) ")
                + Text(RelativeTime.short(post.createdAt.date)).foregroundStyle(SocialStyle.tertiaryText))
                .font(.system(size: 15))
                .lineSpacing(2)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let top = Reactions.top(post.reactions) {
                // Full opacity when I reacted with it, dimmed when I didn't.
                Text(top.emoji)
                    .font(.system(size: 18))
                    .opacity(top.mine ? 1 : 0.4)
                    .accessibilityLabel("Top reaction \(top.emoji)\(top.mine ? ", including yours" : "")")
            }
        }
    }

    private func row<Content: View>(showsSeparator: Bool, @ViewBuilder content: () -> Content) -> some View {
        SocialRow(separatorInset: 64, showsSeparator: showsSeparator) {
            content()
        }
    }

    /// Switches to the Friends tab, optionally pushing a screen there.
    private func open(_ routes: [FriendsRoute]) {
        context.router.show(routes)
        tabSelection.select(.friends)
    }
}
