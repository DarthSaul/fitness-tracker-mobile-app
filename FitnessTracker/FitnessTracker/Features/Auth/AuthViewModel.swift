import Foundation
import AuthenticationServices
import GoogleSignIn
import Observation
import OSLog

@Observable
final class AuthViewModel {
    // MARK: - State
    var isLoading = false
    var error: Error?

    // MARK: - Dependencies
    private let repository: AuthRepository
    private let sessionManager: SessionManager

    init(repository: AuthRepository, sessionManager: SessionManager) {
        self.repository = repository
        self.sessionManager = sessionManager
    }

    // MARK: - Apple Sign-In Handler
    @MainActor
    func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential) async {
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8)
        else {
            Logger.auth.error("Apple credential missing identity token.")
            error = AuthError.missingIdentityToken
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await repository.signInWithApple(
                identityToken: identityToken,
                fullName: credential.fullName
            )
        } catch {
            Logger.auth.error("Sign-in with Apple failed: \(error)")
            self.error = error
        }
    }

    // MARK: - Google Sign-In Handler
    @MainActor
    func handleGoogleIDToken(_ idToken: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await repository.signInWithGoogle(idToken: idToken)
        } catch {
            Logger.auth.error("Sign-in with Google failed: \(error)")
            self.error = error
        }
    }

    @MainActor
    func handleGoogleError(_ error: any Error) {
        if let signInError = error as? GIDSignInError, signInError.code == .canceled {
            Logger.auth.info("Google sign-in canceled by user.")
            return
        }
        Logger.auth.error("Google sign-in error: \(error)")
        self.error = error
    }

    // MARK: - Authorization Error Handler
    @MainActor
    func handleAuthorizationError(_ error: any Error) {
        guard let authError = error as? ASAuthorizationError,
              authError.code == .canceled
        else {
            Logger.auth.error("Sign-in with Apple authorization error: \(error)")
            self.error = error
            return
        }
        // User canceled — not an error worth surfacing
        Logger.auth.info("Apple sign-in canceled by user.")
    }
}

// MARK: - Errors
enum AuthError: LocalizedError {
    case missingIdentityToken
    case googleMissingIDToken
    case googleNoPresentingViewController

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            return "Sign in with Apple did not return a valid token. Please try again."
        case .googleMissingIDToken:
            return "Google sign-in did not return a valid token. Please try again."
        case .googleNoPresentingViewController:
            return "Unable to start Google sign-in. Please try again."
        }
    }
}
