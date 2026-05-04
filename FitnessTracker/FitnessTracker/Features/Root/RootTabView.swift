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
        .environment(liveWorkout)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let session = resumeViewModel?.activeSession {
                ResumeWorkoutBanner(session: session) {
                    liveWorkout.present()
                }
            }
        }
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
}
