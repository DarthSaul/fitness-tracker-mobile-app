import SwiftUI

/// One row in the history list. Used both by the standalone History tab and
/// by the home page's recent-history section, so it stays presentation-only —
/// the parent owns navigation.
struct HistoryRow: View {
    let session: HistorySessionDTO

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
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    private var subtitle: String {
        "\(session.programName) · Week \(session.weekNumber) · Day \(session.dayNumber)"
    }
}
