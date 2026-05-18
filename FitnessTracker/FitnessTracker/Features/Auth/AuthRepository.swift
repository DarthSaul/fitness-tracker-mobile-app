import Foundation
import AuthenticationServices
import OSLog

// MARK: - Repository
final class AuthRepository {
    private let apiClient: any APIClientProtocol
    private let sessionManager: SessionManager

    init(apiClient: any APIClientProtocol, sessionManager: SessionManager) {
        self.apiClient = apiClient
        self.sessionManager = sessionManager
    }

    // MARK: - Sign In With Apple
    func signInWithApple(
        identityToken: String,
        fullName: PersonNameComponents?
    ) async throws {
        let body = AppleSignInBody(
            identityToken: identityToken,
            fullName: fullName.map {
                AppleSignInBody.FullName(
                    givenName: $0.givenName,
                    familyName: $0.familyName
                )
            }
        )

        let response: AuthTokensResponse = try await apiClient.send(.appleSignIn(body))
        Logger.auth.info("Apple sign-in succeeded — persisting tokens.")
        try await sessionManager.didSignIn(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
    }

    // MARK: - Sign In With Google
    func signInWithGoogle(idToken: String) async throws {
        let response: AuthTokensResponse = try await apiClient.send(
            .googleSignIn(GoogleSignInBody(idToken: idToken))
        )
        Logger.auth.info("Google sign-in succeeded — persisting tokens.")
        try await sessionManager.didSignIn(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
    }
}
