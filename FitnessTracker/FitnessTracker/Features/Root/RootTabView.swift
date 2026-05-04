import SwiftUI

/// Top-level shell when the user is authenticated. Hosts the three primary
/// tabs and (in PR #3 follow-ups) the resume-workout banner.
///
/// Convention: each tab's NavigationStack lives at the tab level here.
/// Tab content views (e.g. ProgramListView) should NOT wrap themselves in a
/// NavigationStack — they get one for free from their tab.
struct RootTabView: View {
    var body: some View {
        TabView {
            HomeTab()
                .tabItem { Label("Home", systemImage: "house.fill") }

            ProgramsTab()
                .tabItem { Label("Programs", systemImage: "dumbbell.fill") }

            AnalyticsTab()
                .tabItem { Label("Analytics", systemImage: "chart.line.uptrend.xyaxis") }
        }
    }
}
