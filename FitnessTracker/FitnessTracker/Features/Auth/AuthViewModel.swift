import Foundation
import AuthenticationServices
import GoogleSignIn
import Observation
import OSLog

@Observable
final class AuthViewModel {
    // MARK: - State
    var isLoading = false
    /// Apple/Google failures only — surfaced via the alert. The email form
    /// reports through `formError`/`successMessage` inline instead.
    var error: Error?

    // MARK: - Email Form State
    enum AuthFormMode: Equatable {
        case providers
        case signIn
        case signUp
        case reset
    }

    var formMode: AuthFormMode = .providers
    var email = ""
    var password = ""
    var name = ""
    var formError: String?
    var successMessage: String?
    /// Set when we learn an account is awaiting confirmation (post-signup, or
    /// a sign-in rejected with `email_not_confirmed`). Non-nil shows the
    /// "Resend confirmation email" affordance.
    var pendingConfirmationEmail: String?

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
            // Clear any previously displayed error so a retry-then-cancel
            // doesn't leave a stale message on screen.
            self.error = nil
            return
        }
        Logger.auth.error("Google sign-in error: \(error)")
        self.error = error
    }

    // MARK: - Email Form
    @MainActor
    func openEmailForm() {
        formMode = .signIn
    }

    @MainActor
    func closeEmailForm() {
        formMode = .providers
        email = ""
        password = ""
        name = ""
        formError = nil
        successMessage = nil
        pendingConfirmationEmail = nil
    }

    /// Keeps the email (and any typed password) so hopping between sign-in,
    /// sign-up, and reset doesn't force re-entry.
    @MainActor
    func switchMode(_ mode: AuthFormMode) {
        formMode = mode
        formError = nil
        successMessage = nil
    }

    @MainActor
    func submitEmailForm() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        // Mirror the server's validation so common failures never hit the
        // network. The 8-char minimum applies to sign-up only (web parity —
        // existing accounts may predate a policy change).
        guard !trimmedEmail.isEmpty else {
            formError = AuthError.missingEmail.localizedDescription
            return
        }
        if formMode != .reset, password.isEmpty {
            formError = AuthError.missingPassword.localizedDescription
            return
        }
        if formMode == .signUp, password.count < 8 {
            formError = AuthError.passwordTooShort.localizedDescription
            return
        }

        isLoading = true
        formError = nil
        successMessage = nil
        defer { isLoading = false }

        do {
            switch formMode {
            case .signIn:
                try await repository.signInWithEmail(email: trimmedEmail, password: password)
                // authState flips to .authenticated and ContentView swaps the
                // whole screen — no local cleanup needed.

            case .signUp:
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let outcome = try await repository.signUpWithEmail(
                    email: trimmedEmail,
                    password: password,
                    name: trimmedName.isEmpty ? nil : trimmedName
                )
                if outcome == .confirmationRequired {
                    formMode = .signIn
                    password = ""
                    successMessage = "Check your email to confirm your account, then sign in."
                    pendingConfirmationEmail = trimmedEmail
                }

            case .reset:
                try await repository.requestPasswordReset(email: trimmedEmail)
                successMessage = "If an account exists with that email, a reset link has been sent."

            case .providers:
                return
            }
        } catch {
            Logger.auth.error("Email auth failed: \(error)")
            formError = error.localizedDescription
            if case .httpError(_, _, let data) = error as? APIError,
               APIError.decodeServerErrorCode(from: data) == "email_not_confirmed" {
                pendingConfirmationEmail = trimmedEmail
            }
        }
    }

    @MainActor
    func resendConfirmationEmail() async {
        guard let pendingEmail = pendingConfirmationEmail else { return }

        isLoading = true
        formError = nil
        defer { isLoading = false }

        do {
            try await repository.resendConfirmationEmail(email: pendingEmail)
            successMessage = "Confirmation email sent."
        } catch {
            Logger.auth.error("Resend confirmation failed: \(error)")
            formError = error.localizedDescription
        }
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
    case missingEmail
    case missingPassword
    case passwordTooShort
    /// Server said no confirmation was required but returned no tokens —
    /// a contract violation, not a user-fixable state.
    case invalidSignUpResponse

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            return "Sign in with Apple did not return a valid token. Please try again."
        case .googleMissingIDToken:
            return "Google sign-in did not return a valid token. Please try again."
        case .googleNoPresentingViewController:
            return "Unable to start Google sign-in. Please try again."
        case .missingEmail:
            return "Enter your email address."
        case .missingPassword:
            return "Enter your password."
        case .passwordTooShort:
            return "Password must be at least 8 characters."
        case .invalidSignUpResponse:
            return "Sign-up failed. Please try again."
        }
    }
}
