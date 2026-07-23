import SwiftUI

/// One row in the history list. Used both by the standalone History tab and
/// by the home page's recent-history section, so it stays presentation-only —
/// the parent owns navigation. Renders either flavor of unified-history row:
/// program rows show program · week · day; standalone rows show the workout
/// name and category (falling back to "{category} #{order}" for null names).
struct HistoryRow: View {
    let entry: HistoryEntryDTO

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
            Text("\(entry.completedSets) set\(entry.completedSets == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var headlineDate: String {
        Self.headlineDateFormatter.string(from: entry.completedAt ?? entry.startedAt)
    }

    private var subtitle: String {
        switch entry {
        case .program(let session):
            return "\(session.programName) · Week \(session.weekNumber) · Day \(session.dayNumber)"
        case .standalone(let session):
            let workout = session.standaloneWorkout
            if let name = workout.name, !name.isEmpty {
                return "\(name) · \(workout.category)"
            }
            return workout.displayName
        }
    }
}
