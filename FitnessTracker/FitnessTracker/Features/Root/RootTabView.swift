import SwiftUI

/// Top-level shell when the user is authenticated. Hosts the five tabs
/// (Home, Friends, Progress, Programs, Settings), the resume-workout banner, and the live-workout cover (program or
/// standalone, keyed by LiveWorkoutPresentation.target).
///
/// Convention: each tab's NavigationStack lives at the tab level here.
/// Tab content views (e.g. ProgramListView) should NOT wrap themselves in a
/// NavigationStack — they get one for free from their tab.
struct RootTabView: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PushRegistrar.self) private var pushRegistrar
    @Environment(PushRouter.self) private var pushRouter
    @State private var resumeViewModel: ResumeWorkoutViewModel?
    @State private var tabSelection = TabSelection()
    @State private var liveWorkout = LiveWorkoutPresentation()
    @State private var runChanges = ProgramRunChanges()
    /// Session-scoped (this view exists only while signed in, so a new
    /// sign-in starts fresh): social services and notification state.
    @State private var socialContext: SocialContext
    @State private var notifications: NotificationCenterModel

    init(apiClient: any APIClientProtocol, sessionManager: SessionManager) {
        _socialContext = State(initialValue: SocialContext(
            repository: SocialRepository(apiClient: apiClient),
            sessionManager: sessionManager
        ))
        _notifications = State(initialValue: NotificationCenterModel(
            repository: NotificationsRepository(apiClient: apiClient),
            sessionManager: sessionManager
        ))
    }

    var body: some View {
        TabView(selection: $tabSelection.current) {
            withResumeBanner(HomeTab())
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            withResumeBanner(FriendsTab())
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
                .tag(AppTab.friends)

            withResumeBanner(ProgressTab())
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)

            withResumeBanner(ProgramsTab())
                .tabItem { Label("Programs", systemImage: "dumbbell.fill") }
                .tag(AppTab.programs)

            withResumeBanner(NavigationStack { SettingsView().friendsDestinations() })
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .environment(tabSelection)
        .environment(liveWorkout)
        .environment(runChanges)
        .environment(socialContext)
        .environment(notifications)
        .toastOverlay(socialContext.toasts)
        .task {
            await notifications.syncTimezone()
            await notifications.refreshUnreadCount()
            await openPendingPush()
        }
        .onChange(of: pushRouter.pending) {
            Task { await openPendingPush() }
        }
        .onChange(of: pushRouter.foregroundRevision) {
            Task { await notifications.refreshUnreadCount() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await notifications.syncTimezone() }
        }
        // Ending a run early deletes its in-progress workout server-side, so
        // the banner must not keep offering to resume it.
        .onChange(of: runChanges.revision) {
            Task { await resumeViewModel?.refresh() }
        }
        .fullScreenCover(item: $liveWorkout.target) {
            // Cover dismissed → refresh the resume banner so it disappears
            // when the workout has been completed or abandoned.
            Task { await resumeViewModel?.refresh() }
        } content: { target in
            liveWorkoutCover(for: target)
        }
        .task {
            // Initialize lazily so we capture apiClient from the environment.
            if resumeViewModel == nil {
                resumeViewModel = ResumeWorkoutViewModel(apiClient: apiClient)
            }
            await resumeViewModel?.refresh()
        }
        .task {
            // Signed in (this view only exists while authenticated): ask for
            // notification permission once, and register this launch's APNs
            // token if it arrived before the session did.
            await pushRegistrar.requestAuthorizationIfNeeded()
            await pushRegistrar.registerIfPossible()
        }
    }

    /// Opens a tapped push's target, then marks it read. Follower pushes
    /// carry no actor, so the actor is looked up in the inbox to open their
    /// profile (falling back to Activity).
    private func openPendingPush() async {
        guard let payload = pushRouter.take() else { return }
        var actorId: String?
        if payload.type == .newFollower || payload.type == .followAccepted {
            let recent = try? await notifications.repository.fetch(status: .all, page: .firstPage)
            actorId = recent?.first { $0.id == payload.notificationId }?.actor?.id
        }
        switch NotificationDestination.for(type: payload.type, target: payload.target, actorId: actorId) {
        case .friends(let routes):
            tabSelection.select(.friends)
            socialContext.router.show(routes)
        case .home:
            tabSelection.select(.home)
        }
        _ = try? await notifications.repository.setStatus(id: payload.notificationId, .read)
        await notifications.refreshUnreadCount()
    }

    @ViewBuilder
    private func liveWorkoutCover(for target: LiveWorkoutPresentation.Target) -> some View {
        switch target {
        case .program:
            LiveWorkoutView(viewModel: LiveWorkoutViewModel(
                repository: WorkoutRepository(apiClient: apiClient),
                sessionManager: sessionManager
            ))
        case .standalone(let sessionId):
            StandaloneLiveWorkoutView(viewModel: StandaloneLiveWorkoutViewModel(
                sessionId: sessionId,
                repository: StandaloneWorkoutRepository(apiClient: apiClient),
                sessionManager: sessionManager
            ))
        }
    }

    /// Attaches the resume banner to a tab's *content* (not the TabView), so
    /// it docks in the content's bottom safe area — i.e. directly above the
    /// tab bar — instead of overlapping it.
    private func withResumeBanner<Content: View>(_ content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if let active = resumeViewModel?.activeWorkout {
                switch active {
                case .program(let session):
                    ResumeWorkoutBanner(subtitle: "Week \(session.weekNumber) · Day \(session.dayNumber)") {
                        liveWorkout.present()
                    }
                case .standalone(let session):
                    ResumeWorkoutBanner(subtitle: session.standaloneWorkout.displayName) {
                        liveWorkout.presentStandalone(sessionId: session.id)
                    }
                }
            }
        }
    }
}
