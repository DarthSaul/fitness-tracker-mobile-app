import SwiftUI

/// Who reacted (design-spec 03): filter chips ("All 10", "💪 6", …) over a
/// list of people. Tapping a person opens their profile inside the sheet.
struct ReactorsSheet: View {
    @State private var viewModel: ReactorsViewModel
    @Environment(\.dismiss) private var dismiss

    init(post: PostDTO, initialEmoji: String?, context: SocialContext) {
        _viewModel = State(initialValue: ReactorsViewModel(post: post, initialEmoji: initialEmoji, context: context))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                filters
                list
            }
            .background(SocialStyle.card)
            .toolbar(.hidden, for: .navigationBar)
            .friendsDestinations()
        }
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack {
            Text("Reactions").font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(SocialStyle.fill, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", count: viewModel.totalCount, emoji: nil)
                ForEach(viewModel.summaries) { summary in
                    filterChip(title: summary.emoji, count: summary.count, emoji: summary.emoji)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func filterChip(title: String, count: Int, emoji: String?) -> some View {
        let isSelected = viewModel.selectedEmoji == emoji
        return Button {
            viewModel.selectedEmoji = emoji
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)").opacity(0.6).monospacedDigit()
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(isSelected ? Color.black : Color.primary)
            .background(isSelected ? Color.white : SocialStyle.embed, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var list: some View {
        if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.loadError, viewModel.rows.isEmpty {
            RetryCard(message: APIFailure(error).message) { Task { await viewModel.reload() } }
                .padding(20)
            Spacer()
        } else if viewModel.rows.isEmpty {
            Text("No reactions yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    let rows = viewModel.rows
                    ForEach(rows) { row in
                        NavigationLink(value: FriendsRoute.profile(userId: row.reactor.user.id)) {
                            SocialRow(separatorInset: 72, showsSeparator: row.id != rows.last?.id, verticalPadding: 9) {
                                UserAvatarView(user: row.reactor.user, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.reactor.user.displayName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .lineLimit(1)
                                    Text(row.reactor.user.handle)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Text(row.emoji).font(.system(size: 24))
                            }
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if row.id == rows.last?.id { Task { await viewModel.loadMore() } }
                        }
                    }
                }
            }
        }
    }
}
