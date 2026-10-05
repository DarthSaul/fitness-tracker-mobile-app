import SwiftUI

/// Follow requests (design-spec 07).
struct RequestsView: View {
    @State private var viewModel: RequestsViewModel

    init(context: SocialContext) {
        _viewModel = State(initialValue: RequestsViewModel(context: context))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SocialSegmentedControl(
                    segments: [(.received, viewModel.receivedTitle), (.sent, viewModel.sentTitle)],
                    selection: $viewModel.tab
                )
                content
            }
            .padding(.horizontal, SocialStyle.screenInset)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .background(SocialStyle.background)
        .navigationTitle("Requests")
        .navigationBarTitleDisplayMode(.large)
        .task { if !viewModel.hasLoaded { await viewModel.load() } }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoaded && viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        } else if let error = viewModel.loadError, !viewModel.hasLoaded {
            RetryCard(message: error.message) { Task { await viewModel.load() } }
        } else {
            switch viewModel.tab {
            case .received: receivedTab
            case .sent: sentTab
            }
        }
    }

    // MARK: Received

    @ViewBuilder
    private var receivedTab: some View {
        if viewModel.received.isEmpty {
            emptyCard("No pending requests", detail: "When someone asks to follow you, you'll approve them here.")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SocialGroup {
                    ForEach(viewModel.received) { request in
                        SocialRow(separatorInset: 72, showsSeparator: request.id != viewModel.received.last?.id) {
                            personLink(request.user, subtitle: request.user.handle)
                            receivedControl(request)
                        }
                    }
                }
                GroupFootnote(text: "Approved followers can see your posts and profile stats. Your workouts stay private. They won't be notified if you decline.")
            }
        }

        if !viewModel.approvedRecently.isEmpty {
            SocialGroup(header: "Approved recently") {
                ForEach(viewModel.approvedRecently) { follower in
                    SocialRow(separatorInset: 72, showsSeparator: follower.id != viewModel.approvedRecently.last?.id) {
                        personLink(follower.user, subtitle: "Follows you · \(RelativeTime.short(follower.since))")
                        FollowButton(
                            user: follower.user,
                            outgoing: Binding(
                                get: { viewModel.outgoingState(for: follower.user.id) },
                                set: { viewModel.setOutgoing($0, for: follower.user.id) }
                            )
                        )
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func receivedControl(_ request: FollowRequestDTO) -> some View {
        let isWorking = viewModel.workingIds.contains(request.id)
        switch viewModel.state(for: request) {
        case .pending:
            HStack(spacing: 8) {
                Button("Approve") { Task { await viewModel.approve(request) } }
                    .buttonStyle(.pill(.blue))
                Button {
                    Task { await viewModel.decline(request) }
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
            .disabled(isWorking)
        case .approved:
            Button {
                Task { await viewModel.followBack(request) }
            } label: {
                Label("Follow back", systemImage: "plus")
            }
            .buttonStyle(.pill(.tinted))
            .disabled(isWorking)
        case .followed(let state):
            Text(state == .requested ? "Requested" : "Following")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(SocialStyle.fill, in: Capsule())
        case .declined:
            Text("Declined")
                .font(.system(size: 14))
                .foregroundStyle(SocialStyle.tertiaryText)
        }
    }

    // MARK: Sent

    @ViewBuilder
    private var sentTab: some View {
        if viewModel.sent.isEmpty {
            emptyCard("No sent requests", detail: "Requests you send to private accounts wait here until they're approved.")
        } else {
            SocialGroup {
                ForEach(viewModel.sent) { request in
                    SocialRow(separatorInset: 72, showsSeparator: request.id != viewModel.sent.last?.id) {
                        personLink(request.user, subtitle: "\(request.user.handle) · \(RelativeTime.short(request.createdAt))")
                        let cancelled = viewModel.cancelledSentIds.contains(request.id)
                        Button(cancelled ? "Request" : "Requested") {
                            Task {
                                if cancelled {
                                    await viewModel.requestAgain(request)
                                } else {
                                    await viewModel.cancel(request)
                                }
                            }
                        }
                        .buttonStyle(.pill(cancelled ? .blue : .gray))
                        .disabled(viewModel.workingIds.contains(request.id))
                        .accessibilityHint(cancelled ? "Sends the request again" : "Cancels your request")
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func personLink(_ user: PublicUserDTO, subtitle: String) -> some View {
        NavigationLink(value: FriendsRoute.profile(userId: user.id)) {
            HStack(spacing: 12) {
                UserAvatarView(user: user, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func emptyCard(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(SocialStyle.card, in: RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous))
    }
}
