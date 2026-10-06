import SwiftUI

/// "3 follow requests / Theo, Ana and 1 other" with an avatar stack: the
/// content of the feed's shortcut card and Activity's pinned row, both of
/// which open Requests. Callers supply the tap target and the card
/// background, and hide it when there are no requests.
struct FollowRequestsSummaryRow: View {
    let requests: [FollowRequestDTO]
    let summary: String
    /// Activity shows "Follow requests" plus a red count capsule; the feed
    /// puts the count in the title.
    var showsCountBadge = false

    var body: some View {
        HStack(spacing: 12) {
            AvatarStack(users: requests.map(\.user))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsCountBadge {
                Text("\(requests.count)")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Color.red, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SocialStyle.tertiaryText)
        }
        .contentShape(Rectangle())
    }

    private var title: String {
        if showsCountBadge { return "Follow requests" }
        return "\(requests.count) follow request\(requests.count == 1 ? "" : "s")"
    }
}
