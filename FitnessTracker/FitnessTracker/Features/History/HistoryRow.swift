import SwiftUI

/// One row in the history list. Used both by the standalone History tab and
/// by the home page's recent-history section, so it stays presentation-only —
/// the parent owns navigation.
struct HistoryRow: View {
    let session: HistorySessionDTO

    /// Cached so repeated row renders don't allocate a new formatter per row.
    /// `setLocalizedDateFormatFromTemplate` adapts to the user's locale (avoids
    /// hardcoding "EEE, MMM d", which reads oddly outside en-US).
    private static let headlineDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headlineDate)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(session.count.completedSets) set\(session.count.completedSets == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var headlineDate: String {
        let date = session.completedAt ?? session.startedAt
        return Self.headlineDateFormatter.string(from: date)
    }

    private var subtitle: String {
        "\(session.programName) · Week \(session.weekNumber) · Day \(session.dayNumber)"
    }
}
