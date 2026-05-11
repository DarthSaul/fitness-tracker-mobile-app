import SwiftUI
import SwiftData
import Sentry
import OSLog

@main
struct FitnessTrackerApp: App {
    // MARK: - Core Services (created once at app lifetime)
    private let keychain = KeychainService()
    private let tokenStore = TokenStore()
    private let sessionManager: SessionManager
    private let apiClient: APIClient
    private let modelContainer: ModelContainer

    @AppStorage(appAppearanceStorageKey) private var appearanceRaw: String = AppAppearance.system.rawValue

    init() {
        // Local copy avoids capturing self in the escaping Sentry closure.
        let isDebug: Bool = {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }()

        // MARK: Sentry (before any other setup so crashes during init are captured)
        if let dsn = APIConfig.sentryDSN {
            SentrySDK.start { options in
                options.dsn = dsn
                options.environment = isDebug ? "debug" : "release"
                options.enableAutoSessionTracking = true
                options.tracesSampleRate = isDebug ? 1.0 : 0.2
            }
        } else {
            Logger.app.info("Sentry disabled — DSN not configured (xcconfig still has the placeholder).")
        }

        // MARK: Session
        let sm = SessionManager(keychain: keychain, tokenStore: tokenStore)
        sessionManager = sm

        // MARK: Networking
        apiClient = APIClient(
            tokenStore: tokenStore,
            tokenRefresher: sm.tokenRefresher
        )
        sm.apiClient = apiClient

        // MARK: Persistence
        do {
            modelContainer = try PersistenceContainer.makeShared()
        } catch {
            // ModelContainer failure is unrecoverable — crash with a clear message.
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }

        Logger.data.info("App initialized. API base: \(APIConfig.baseURL.absoluteString)")
    }

    // MARK: - Scene
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(apiClient)
                .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme)
                .task { await sessionManager.bootstrap() }
        }
        .modelContainer(modelContainer)
    }
}
