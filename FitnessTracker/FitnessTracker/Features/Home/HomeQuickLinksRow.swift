import SwiftUI

struct HomeQuickLinksRow: View {
    @Environment(TabSelection.self) private var tabSelection

    var body: some View {
        HStack(spacing: 12) {
            QuickLinkCard(title: "Analytics", systemImage: "chart.line.uptrend.xyaxis") {
                tabSelection.select(.analytics)
            }
            QuickLinkCard(title: "Browse Programs", systemImage: "list.bullet.rectangle") {
                tabSelection.select(.programs)
            }
        }
    }
}

private struct QuickLinkCard: View {
    let title: String
    let systemImage: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
