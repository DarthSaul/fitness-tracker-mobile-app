import SwiftUI

/// The Follow / Request / Requested / Following pill. Owns an optimistic copy
/// of `outgoing`, reports changes through `onChange`, and confirms before
/// unfollowing.
struct FollowButton: View {
    let user: PublicUserDTO
    @Binding var outgoing: FollowState
    var fullWidth = false
    var height: CGFloat = 34

    @Environment(SocialContext.self) private var context
    @State private var isWorking = false
    @State private var confirmUnfollow = false

    private var state: FollowButtonState {
        FollowButtonState(visibility: user.profileVisibility, outgoing: outgoing)
    }

    var body: some View {
        Button {
            switch state {
            case .follow, .request: Task { await follow() }
            case .requested: Task { await unfollow() }
            case .following: confirmUnfollow = true
            }
        } label: {
            HStack(spacing: 5) {
                if state == .following {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                }
                Text(fullWidth && state == .request ? "Request to follow" : state.title)
            }
        }
        .buttonStyle(.pill(state == .follow || state == .request ? .blue : .gray, height: height, fullWidth: fullWidth))
        .disabled(isWorking)
        .sensoryFeedback(.selection, trigger: outgoing)
        .confirmationAlert(
            "Unfollow \(user.displayName)?",
            isPresented: $confirmUnfollow,
            message: user.profileVisibility == .private
                ? "Their account is private, so you'll need to request again to see their posts."
                : "Their posts will no longer appear in your feed.",
            confirmLabel: "Unfollow",
            confirmRole: .destructive
        ) {
            Task { await unfollow() }
        }
        .accessibilityLabel("\(state.title), \(user.displayName)")
    }

    private func follow() async {
        let previous = outgoing
        isWorking = true
        defer { isWorking = false }
        outgoing = FollowButtonState.optimisticOutgoingAfterFollowing(visibility: user.profileVisibility)
        if let result = await FollowActions(context: context).follow(user) {
            outgoing = result
        } else {
            outgoing = previous
        }
    }

    private func unfollow() async {
        let previous = outgoing
        isWorking = true
        defer { isWorking = false }
        outgoing = .none
        if await FollowActions(context: context).unfollow(user) == nil {
            outgoing = previous
        }
    }
}
