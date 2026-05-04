import SwiftUI
import OSLog

/// Top-level shell when the user is authenticated. Hosts the three primary
/// tabs and the resume-workout banner.
///
/// Convention: each tab's NavigationStack lives at the tab level here.
/// Tab content views (e.g. ProgramListView) should NOT wrap themselves in a
/// NavigationStack — they get one for free from their tab.
struct RootTabView: View {
    @Environment(APIClient.self) private var apiClient
    @State private var resumeViewModel: ResumeWorkoutViewModel?
    @State private var tabSelection = TabSelection()

    var body: some View {
        TabView(selection: $tabSelection.current) {
            HomeTab()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            ProgramsTab()
                .tabItem { Label("Programs", systemImage: "dumbbell.fill") }
                .tag(AppTab.programs)

            AnalyticsTab()
                .tabItem { Label("Analytics", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.analytics)
        }
        .environment(tabSelection)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let session = resumeViewModel?.activeSession {
                ResumeWorkoutBanner(session: session) {
                    // PR #7 will navigate into the live workout view.
                    Logger.app.info("Resume banner tapped — deep link arrives in PR #7.")
                }
            }
        }
        .task {
            // Initialize lazily so we capture apiClient from the environment.
            if resumeViewModel == nil {
                resumeViewModel = ResumeWorkoutViewModel(apiClient: apiClient)
            }
            await resumeViewModel?.refresh()
        }
    }
}
