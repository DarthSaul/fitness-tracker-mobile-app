import SwiftUI

/// Top-level shell when the user is authenticated. Hosts the three primary
/// tabs, the resume-workout banner, and the live-workout sheet.
///
/// Convention: each tab's NavigationStack lives at the tab level here.
/// Tab content views (e.g. ProgramListView) should NOT wrap themselves in a
/// NavigationStack — they get one for free from their tab.
struct RootTabView: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager
    @State private var resumeViewModel: ResumeWorkoutViewModel?
    @State private var tabSelection = TabSelection()
    @State private var liveWorkout = LiveWorkoutPresentation()

    var body: some View {
        TabView(selection: $tabSelection.current) {
            withResumeBanner(HomeTab())
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            withResumeBanner(HistoryTab())
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)

            withResumeBanner(AnalyticsTab())
                .tabItem { Label("Analytics", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.analytics)

            withResumeBanner(ProgramsTab())
                .tabItem { Label("Programs", systemImage: "dumbbell.fill") }
                .tag(AppTab.programs)

            withResumeBanner(NavigationStack { SettingsView() })
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .environment(tabSelection)
        .environment(liveWorkout)
        .fullScreenCover(isPresented: $liveWorkout.isPresented) {
            // Sheet dismissed → refresh the resume banner so it disappears
            // when the workout has been completed or abandoned.
            Task { await resumeViewModel?.refresh() }
        } content: {
            LiveWorkoutView(viewModel: LiveWorkoutViewModel(
                repository: WorkoutRepository(apiClient: apiClient),
                sessionManager: sessionManager
            ))
        }
        .task {
            // Initialize lazily so we capture apiClient from the environment.
            if resumeViewModel == nil {
                resumeViewModel = ResumeWorkoutViewModel(apiClient: apiClient)
            }
            await resumeViewModel?.refresh()
        }
    }

    /// Attaches the resume banner to a tab's *content* (not the TabView), so
    /// it docks in the content's bottom safe area — i.e. directly above the
    /// tab bar — instead of overlapping it.
    private func withResumeBanner<Content: View>(_ content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if let session = resumeViewModel?.activeSession {
                ResumeWorkoutBanner(session: session) {
                    liveWorkout.present()
                }
            }
        }
    }
}
