import SwiftUI

/// Settings → Blocked accounts (not mocked; standard list).
struct BlockedAccountsView: View {
    let context: SocialContext
    var onCountChange: (Int) -> Void = { _ in }

    @State private var users: [BlockedUserDTO] = []
    @State private var hasLoaded = false
    @State private var loadError: APIFailure?
    @State private var unblockCandidate: BlockedUserDTO?

    var body: some View {
        List {
            if let loadError, !hasLoaded {
                Section {
                    RetryCard(message: loadError.message) { Task { await load() } }
                }
                .listRowBackground(Color.clear)
            } else if hasLoaded && users.isEmpty {
                ContentUnavailableView(
                    "No blocked accounts",
                    systemImage: "hand.raised",
                    description: Text("People you block can't find you or see your posts, and you won't see theirs.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(users) { blocked in
                        HStack(spacing: 12) {
                            UserAvatarView(user: blocked.user, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(blocked.user.displayName).font(.body.weight(.semibold))
                                Text(blocked.user.handle).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unblock") { unblockCandidate = blocked }
                                .buttonStyle(.pill(.gray))
                        }
                    }
                } footer: {
                    Text("Unblocking doesn't restore follows that blocking removed.")
                }
            }
        }
        .overlay {
            if !hasLoaded && loadError == nil { ProgressView() }
        }
        .navigationTitle("Blocked Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !hasLoaded { await load() } }
        .refreshable { await load() }
        .confirmationAlert(
            "Unblock \(unblockCandidate?.user.displayName ?? "")?",
            isPresented: Binding(get: { unblockCandidate != nil }, set: { if !$0 { unblockCandidate = nil } }),
            message: "They'll be able to find you and follow or request to follow you again. Follows removed by the block aren't restored.",
            confirmLabel: "Unblock"
        ) {
            if let blocked = unblockCandidate {
                Task {
                    if await SafetyActions(context: context).unblock(blocked.user) {
                        users.removeAll { $0.id == blocked.id }
                        onCountChange(users.count)
                    }
                }
            }
        }
    }

    private func load() async {
        loadError = nil
        do {
            users = try await context.repository.fetchBlocked()
            hasLoaded = true
            onCountChange(users.count)
        } catch {
            loadError = await context.failure(from: error)
        }
    }
}
