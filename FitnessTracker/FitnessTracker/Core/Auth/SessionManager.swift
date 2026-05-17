import Foundation
import Observation
import OSLog
import Sentry

@Observable
final class SessionManager {
    // MARK: - State
    private(set) var authState: AuthState = .loading
    /// Cached profile from GET /api/auth/me. Populated by `loadProfile()` after
    /// authenticated transitions; cleared on sign-out. UI (Settings) reads this
    /// directly so the name/email render without re-fetching per view.
    private(set) var userProfile: UserProfile?

    // MARK: - Dependencies
    let tokenStore: TokenStore
    let tokenRefresher: TokenRefresher
    private let keychain: KeychainService
    /// Set by the app shell after construction so SessionManager itself can
    /// avoid an init-time dependency on APIClient (APIClient depends on
    /// TokenRefresher, which lives on SessionManager — circular if injected).
    var apiClient: (any APIClientProtocol)?

    // MARK: - Init
    init(keychain: KeychainService, tokenStore: TokenStore) {
        self.keychain = keychain
        self.tokenStore = tokenStore
        self.tokenRefresher = TokenRefresher(keychain: keychain, tokenStore: tokenStore)
    }

    // MARK: - Session Bootstrap
    // Call once at app launch. Tries to silently refresh using the stored refresh token.
    func bootstrap() async {
        Logger.auth.info("Bootstrapping session...")
        do {
            try await tokenRefresher.refresh()
            let token = await tokenStore.getAccessToken()
            let userId = extractUserId(from: token)
            authState = userId.map { .authenticated(userId: $0) } ?? .unauthenticated
            Logger.auth.info("Session bootstrap: authenticated as \(userId ?? "unknown", privacy: .private)")
            if let userId {
                SentrySDK.setUser(Sentry.User(userId: userId))
                await loadProfile()
            }
        } catch {
            Logger.auth.info("Session bootstrap: no valid session — showing sign-in.")
            authState = .unauthenticated
        }
    }

    // MARK: - Profile

    /// Fetches GET /api/auth/me and caches the result. Logs and swallows errors
    /// — Settings falls back to a generic header when the profile is missing.
    func loadProfile() async {
        guard let apiClient else {
            Logger.auth.error("loadProfile called before apiClient was wired")
            return
        }
        // Capture the user this request is for. If the session changes while
        // the request is in flight (sign-out, or sign-out then sign-in as a
        // different user), the result must not be written into the new session.
        guard case .authenticated(let initiatingUserId) = authState else { return }
        do {
            let profile: UserProfile = try await apiClient.send(.getMe)
            // Drop the result if the session changed while the request was in
            // flight — otherwise we'd write this profile/identity into a
            // signed-out or different-user session.
            guard case .authenticated(let currentUserId) = authState,
                  currentUserId == initiatingUserId else { return }
            self.userProfile = profile
            // Enrich the Sentry identity with email now that the profile has
            // landed. ID was already set at sign-in/bootstrap so events stay
            // attributable even if this fetch failed.
            let sentryUser = Sentry.User(userId: currentUserId)
            sentryUser.email = profile.email
            SentrySDK.setUser(sentryUser)
        } catch {
            Logger.auth.error("loadProfile failed: \(error)")
        }
    }

    // MARK: - Sign Out
    func signOut() async {
        Logger.auth.info("Signing out.")

        // Surface keychain failures in the log so they aren't lost, but always
        // continue to clear in-memory state — the user requested sign-out, and
        // a stale Keychain entry is preferable to a stale in-memory token.
        do {
            try await keychain.delete(.refreshToken)
        } catch {
            Logger.auth.error("Failed to delete refreshToken from Keychain during sign-out: \(error)")
        }
        do {
            try await keychain.delete(.appleUserID)
        } catch {
            Logger.auth.error("Failed to delete appleUserID from Keychain during sign-out: \(error)")
        }

        await tokenStore.clear()
        userProfile = nil
        authState = .unauthenticated
        SentrySDK.setUser(nil)
    }

    // MARK: - Authenticated Transition
    func didSignIn(accessToken: String, refreshToken: String) async throws {
        // Persist first. If the Keychain save fails, throw before we mutate
        // any in-memory state — that way we never end up with an access token
        // in memory but no matching refresh token on disk (a partial session
        // that would later silently fail to refresh).
        try await keychain.save(refreshToken, for: .refreshToken)
        await tokenStore.set(access: accessToken)
        let userId = extractUserId(from: accessToken) ?? "unknown"
        authState = .authenticated(userId: userId)
        SentrySDK.setUser(Sentry.User(userId: userId))
        await loadProfile()
    }

    // MARK: - Helpers
    // Decodes userId from the JWT access token's payload without validating the signature.
    // Validation happens server-side; we only need the subject claim locally.
    private func extractUserId(from token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3 else { return nil }
        var payload = parts[1]
        // Base64url → Base64
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard
            let data = Data(base64Encoded: padded),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sub = json["sub"] as? String
        else { return nil }
        return sub
    }
}
