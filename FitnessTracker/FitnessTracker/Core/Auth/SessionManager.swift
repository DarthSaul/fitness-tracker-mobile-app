import Foundation
import Observation
import OSLog

@Observable
final class SessionManager {
    // MARK: - State
    private(set) var authState: AuthState = .loading

    // MARK: - Dependencies
    let tokenStore: TokenStore
    let tokenRefresher: TokenRefresher
    private let keychain: KeychainService

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
        } catch {
            Logger.auth.info("Session bootstrap: no valid session — showing sign-in.")
            authState = .unauthenticated
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
        authState = .unauthenticated
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
