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

    // MARK: - Email
    func signInWithEmail(email: String, password: String) async throws {
        let response: AuthTokensResponse = try await apiClient.send(
            .emailSignIn(EmailSignInBody(email: email, password: password))
        )
        Logger.auth.info("Email sign-in succeeded — persisting tokens.")
        try await sessionManager.didSignIn(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
    }

    func signUpWithEmail(
        email: String, password: String, name: String?
    ) async throws -> EmailSignUpOutcome {
        let response: EmailSignUpResponse = try await apiClient.send(
            .emailSignUp(EmailSignUpBody(email: email, password: password, name: name))
        )

        if response.confirmationRequired {
            Logger.auth.info("Email sign-up created — awaiting confirmation.")
            return .confirmationRequired
        }

        guard let accessToken = response.accessToken,
              let refreshToken = response.refreshToken
        else {
            throw AuthError.invalidSignUpResponse
        }

        Logger.auth.info("Email sign-up succeeded — persisting tokens.")
        try await sessionManager.didSignIn(
            accessToken: accessToken,
            refreshToken: refreshToken
        )
        return .signedIn
    }

    func requestPasswordReset(email: String) async throws {
        try await apiClient.send(.requestPasswordReset(PasswordResetBody(email: email)))
        Logger.auth.info("Password reset email requested.")
    }

    func resendConfirmationEmail(email: String) async throws {
        try await apiClient.send(.resendConfirmationEmail(ResendConfirmationBody(email: email)))
        Logger.auth.info("Confirmation email resend requested.")
    }
}

/// Result of an email sign-up. `.confirmationRequired` means no session was
/// established — the user must confirm via the emailed link, then sign in.
enum EmailSignUpOutcome: Equatable {
    case confirmationRequired
    case signedIn
}
