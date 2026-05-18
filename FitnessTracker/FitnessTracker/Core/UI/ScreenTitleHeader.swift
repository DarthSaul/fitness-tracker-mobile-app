import SwiftUI

/// Standard top-of-screen title for the primary tab roots. Replaces the system
/// large navigation title: now that Settings lives in the bottom tab bar (not a
/// nav-bar button), the title can sit flush at the top with no reserved chrome.
/// The leading title is paired with a trailing emoji that mirrors the tab's
/// menu icon, to make each screen a little more inviting.
struct ScreenTitleHeader: View {
    let title: String
    let emoji: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.largeTitle.bold())
            Spacer(minLength: 12)
            Text(emoji)
                .font(.largeTitle)
                .accessibilityHidden(true)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
