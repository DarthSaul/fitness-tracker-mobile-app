import SwiftUI

/// Analytics tab — dashboard stats, exercise selector, e1RM Swift Charts
/// sparkline, and session history arrive in PR #8.
struct AnalyticsTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Analytics",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Strength tracking and session history will live here.")
            )
            .navigationTitle("Analytics")
        }
    }
}
