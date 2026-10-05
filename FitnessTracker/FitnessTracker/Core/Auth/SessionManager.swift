import Foundation
import Observation
import OSLog
import Sentry
import UserNotifications

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
    /// Set by the app shell. Supplies the APNs token for a user-initiated
    /// sign-out and is told to re-register after the next sign-in.
    var pushRegistrar: PushRegistrar?

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

    /// Replaces the cached profile with a fresh `PATCH /api/auth/me` response,
    /// if it belongs to the signed-in user.
    func applyProfile(_ profile: UserProfile) {
        guard case .authenticated(let userId) = authState, userId == profile.id else { return }
        userProfile = profile
    }

    /// The signed-in user's id, for "My profile" and `isMine` checks.
    var currentUserId: String? {
        if case .authenticated(let userId) = authState { return userId }
        return nil
    }

    // MARK: - Sign Out

    /// The user tapped Sign Out. Revokes the session server-side — the
    /// refresh token, and this phone's push token so the next person to use
    /// it doesn't get this user's notifications — then clears local state.
    ///
    /// `POST /api/auth/logout` is best-effort: if it fails (offline, server
    /// down) the user is still signed out locally. It's skipped when there's
    /// no refresh token, since that token is what proves who is signing out.
    func signOutByUser() async {
        Logger.auth.info("User-initiated sign-out.")
        // Stop push registration first (and let any in-flight one finish),
        // so a registration can't land after logout and re-activate the
        // token it revokes. The local teardown below lifts the suspension.
        await pushRegistrar?.suspendRegistration()
        if let apiClient, let refreshToken = try? await keychain.load(.refreshToken) {
            let body = LogoutBody(refreshToken: refreshToken, deviceToken: pushRegistrar?.deviceToken)
            do {
                try await apiClient.send(.logout(body))
            } catch {
                Logger.auth.error("Logout request failed; signing out locally anyway: \(error)")
            }
        }
        // This user's unread count shouldn't stay on the icon for whoever
        // uses the phone next. (A forced sign-out keeps it: the pushes, and
        // their badge, keep coming.)
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
        await signOut()
    }

    /// Clears local session state only: Keychain, in-memory token, cached
    /// profile, Sentry identity. No API call.
    ///
    /// This is the **forced** sign-out every `.unauthorized` path uses (the
    /// refresh token is already dead), and the teardown after account
    /// deletion (the server already revoked everything). It deliberately
    /// leaves the device registered for push, so workout reminders keep
    /// reaching the user's phone; tapping one routes through sign-in. For the
    /// Sign Out button, use `signOutByUser()`.
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
        // Whoever signs in next registers the token again (re-activating it
        // after a user sign-out revoked it, or moving it to a new user).
        pushRegistrar?.resetRegistration()
    }

    // MARK: - Delete Account
    /// DELETE /api/auth/me, then run the full local sign-out teardown
    /// (Keychain, token store, profile, authState, Sentry). A 404 means the
    /// account is already gone (a retried delete, or deletion from another
    /// device) and is treated as success. On any other error this rethrows
    /// WITHOUT touching local state — the Keychain is only cleared once the
    /// server has confirmed the account no longer exists.
    func deleteAccount() async throws(APIError) {
        guard let apiClient else {
            // Unlike loadProfile(), a silent return here would read as a
            // successful deletion — throw instead. Unreachable in practice:
            // the app shell wires apiClient before any UI exists.
            Logger.auth.error("deleteAccount called before apiClient was wired")
            throw APIError.unknown(URLError(.unknown))
        }
        Logger.auth.info("Deleting account…")
        do throws(APIError) {
            try await apiClient.send(.deleteAccount)
        } catch APIError.httpError(let statusCode, _, _) where statusCode == 404 {
            Logger.auth.info("Delete account: 404 — already deleted; proceeding with teardown.")
        }
        // Server confirmed the account is gone (200 or 404) — now, and only
        // now, clear local state. The server already revoked refresh tokens
        // and device registrations, so no logout/unregister calls follow.
        await signOut()
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

    #if DEBUG
    /// Test/preview only: directly install an authState without going through
    /// `bootstrap()` / `didSignIn()`. Production callers must use those entry
    /// points so the keychain, token store, and Sentry identity stay in sync.
    func _setAuthStateForTesting(_ state: AuthState) {
        self.authState = state
    }
    #endif

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
