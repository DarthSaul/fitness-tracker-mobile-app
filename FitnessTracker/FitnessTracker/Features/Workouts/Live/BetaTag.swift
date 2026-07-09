import SwiftUI

/// Small "Beta" status pill for flagging in-progress features (e.g. the Core
/// circuit). Kept intentionally simple: a filled capsule with uppercase-ish
/// caption text.
struct BetaTag: View {
    var body: some View {
        Text("Beta")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange))
    }
}
