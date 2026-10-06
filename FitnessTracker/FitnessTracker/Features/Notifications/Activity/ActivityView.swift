import SwiftUI

/// Activity (design-spec 06), reached from the bell.
struct ActivityView: View {
    @State private var viewModel: ActivityViewModel
    @Environment(SocialContext.self) private var context
    @Environment(TabSelection.self) private var tabSelection

    init(context: SocialContext, notifications: NotificationCenterModel) {
        _viewModel = State(initialValue: ActivityViewModel(context: context, notifications: notifications))
    }

    var body: some View {
        List {
            if !viewModel.incomingRequests.isEmpty {
                // Its own section with the list's card background, so it's
                // as wide as the activity cards below. A button rather than
                // a NavigationLink, which the list would give a second,
                // system chevron outside the row's own.
                Section {
                    Button {
                        context.router.open(.requests)
                    } label: {
                        FollowRequestsSummaryRow(
                            requests: viewModel.incomingRequests,
                            summary: viewModel.requestsSummary,
                            showsCountBadge: true
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(SocialStyle.card)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            }

            content
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SocialStyle.background)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark read") { Task { await viewModel.markAllRead() } }
                    .disabled(!viewModel.items.contains(where: \.isUnread))
            }
        }
        .task { await viewModel.open() }
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        let inbox = viewModel.inbox
        if !inbox.hasLoaded && inbox.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        } else if let error = inbox.loadError, inbox.items.isEmpty {
            RetryCard(message: APIFailure(error).message) { Task { await viewModel.refresh() } }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        } else if inbox.hasLoaded && viewModel.items.isEmpty {
            ContentUnavailableView(
                "No activity yet",
                systemImage: "bell",
                description: Text("Reactions to your posts and new followers show up here.")
            )
            .listRowBackground(Color.clear)
        } else {
            ForEach(viewModel.sections) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item)
                            .listRowBackground(SocialStyle.card)
                            .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 56 }
                            .swipeActions {
                                Button("Dismiss", role: .destructive) {
                                    Task { await viewModel.dismiss(item) }
                                }
                            }
                            .onAppear {
                                if item.id == viewModel.items.last?.id {
                                    Task { await inbox.loadMoreIfNeeded(currentItem: inbox.items[inbox.items.count - 1]) }
                                }
                            }
                    }
                } header: {
                    SectionHeaderText(group.section.rawValue)
                }
            }

            if inbox.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if let error = inbox.loadMoreError {
                RetryCard(message: APIFailure(error).message) { Task { await inbox.retryLoadMore() } }
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func row(_ item: ActivityItem) -> some View {
        Button {
            viewModel.markRead(item)
            open(item.destination)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    avatar(item)
                    if item.isUnread {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: -13)
                            .accessibilityLabel("Unread")
                    }
                }
                (sentence(item) + Text(" ") + Text(RelativeTime.short(item.createdAt)).foregroundStyle(SocialStyle.tertiaryText))
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.kind == .followAccepted {
                    Text("Following")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(SocialStyle.fill, in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func sentence(_ item: ActivityItem) -> Text {
        let text = item.text
        if let name = text.name {
            return Text(name).fontWeight(.semibold) + Text(" \(text.rest)")
        }
        return Text(text.rest)
    }

    @ViewBuilder
    private func avatar(_ item: ActivityItem) -> some View {
        if let actor = item.actors.first {
            UserAvatarView(user: actor, size: 44)
        } else {
            Image(systemName: item.kind == .workoutUnfinished ? "figure.strengthtraining.traditional" : "calendar")
                .font(.system(size: 19))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(SocialStyle.brandGradient, in: Circle())
        }
    }

    private func open(_ destination: NotificationDestination) {
        switch destination {
        case .friends(let routes):
            for route in routes { context.router.open(route) }
        case .home:
            tabSelection.select(.home)
        }
    }
}
