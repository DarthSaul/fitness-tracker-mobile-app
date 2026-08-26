import Foundation
import Testing
@testable import FitnessTracker

/// Pure form-state tests — no test here completes `didSignIn`, so nothing
/// touches the real keychain (see the caveat in AuthRepositoryEmailTests).
/// Client-side validation is proven to short-circuit the network because an
/// unstubbed MockAPIClient throws `.missingHandler` — the tests would surface
/// that message in `formError` if a request escaped.
@Suite("AuthViewModel email form")
@MainActor
struct AuthViewModelEmailFormTests {
    private func makeViewModel() -> (AuthViewModel, MockAPIClient) {
        let manager = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        let client = MockAPIClient()
        manager.apiClient = client
        manager._setAuthStateForTesting(.unauthenticated)
        let repository = AuthRepository(apiClient: client, sessionManager: manager)
        return (AuthViewModel(repository: repository, sessionManager: manager), client)
    }

    // MARK: - Client-side validation

    @Test("empty email fails validation without a network call")
    func emptyEmailShortCircuits() async {
        let (viewModel, _) = makeViewModel()
        viewModel.openEmailForm()
        viewModel.email = "   "
        viewModel.password = "testpass123"

        await viewModel.submitEmailForm()

        #expect(viewModel.formError == AuthError.missingEmail.localizedDescription)
    }

    @Test("empty password fails validation for sign-in")
    func emptyPasswordShortCircuits() async {
        let (viewModel, _) = makeViewModel()
        viewModel.openEmailForm()
        viewModel.email = "jane@example.com"

        await viewModel.submitEmailForm()

        #expect(viewModel.formError == AuthError.missingPassword.localizedDescription)
    }

    @Test("short password fails validation for sign-up only")
    func shortPasswordSignUpOnly() async {
        let (viewModel, client) = makeViewModel()
        viewModel.openEmailForm()
        viewModel.switchMode(.signUp)
        viewModel.email = "jane@example.com"
        viewModel.password = "short"

        await viewModel.submitEmailForm()
        #expect(viewModel.formError == AuthError.passwordTooShort.localizedDescription)

        // The same password on sign-in reaches the network (server decides) —
        // mirror of the web, where minlength only guards the sign-up form.
        client.handlers["POST /api/auth/native/email/signin"] = { _ in
            throw APIError.httpError(statusCode: 401, message: "Invalid email or password.", data: Data())
        }
        viewModel.switchMode(.signIn)
        await viewModel.submitEmailForm()
        #expect(viewModel.formError == "Invalid email or password.")
    }

    // MARK: - Mode switching

    @Test("switching modes clears messages and the resend affordance but keeps the email")
    func switchModeClearsMessages() {
        let (viewModel, _) = makeViewModel()
        viewModel.openEmailForm()
        viewModel.email = "jane@example.com"
        viewModel.formError = "boom"
        viewModel.successMessage = "done"
        viewModel.pendingConfirmationEmail = "jane@example.com"

        viewModel.switchMode(.reset)

        #expect(viewModel.formMode == .reset)
        #expect(viewModel.formError == nil)
        #expect(viewModel.successMessage == nil)
        #expect(viewModel.pendingConfirmationEmail == nil)
        #expect(viewModel.email == "jane@example.com")
    }

    @Test("closing the form resets all state")
    func closeFormResets() {
        let (viewModel, _) = makeViewModel()
        viewModel.openEmailForm()
        viewModel.email = "jane@example.com"
        viewModel.password = "testpass123"
        viewModel.name = "Jane"
        viewModel.formError = "boom"
        viewModel.pendingConfirmationEmail = "jane@example.com"

        viewModel.closeEmailForm()

        #expect(viewModel.formMode == .providers)
        #expect(viewModel.email.isEmpty)
        #expect(viewModel.password.isEmpty)
        #expect(viewModel.name.isEmpty)
        #expect(viewModel.formError == nil)
        #expect(viewModel.pendingConfirmationEmail == nil)
    }

    // MARK: - Sign-up confirmation flow

    @Test("confirmation-required sign-up flips to sign-in with the check-email message")
    func signUpConfirmationFlow() async {
        let (viewModel, client) = makeViewModel()
        client.handlers["POST /api/auth/native/email/signup"] = { _ in
            Data(#"{"confirmationRequired":true}"#.utf8)
        }
        viewModel.openEmailForm()
        viewModel.switchMode(.signUp)
        viewModel.email = " jane@example.com "
        viewModel.password = "testpass123"

        await viewModel.submitEmailForm()

        #expect(viewModel.formMode == .signIn)
        #expect(viewModel.password.isEmpty)
        #expect(viewModel.successMessage == "Check your email to confirm your account, then sign in.")
        #expect(viewModel.pendingConfirmationEmail == "jane@example.com")
        #expect(viewModel.formError == nil)
    }

    @Test("unconfirmed sign-in surfaces the resend affordance via the error code")
    func signInUnconfirmedSetsPending() async {
        let (viewModel, client) = makeViewModel()
        let errorBody = Data(#"{"statusMessage":"Please confirm your email before signing in.","data":{"code":"email_not_confirmed"}}"#.utf8)
        client.handlers["POST /api/auth/native/email/signin"] = { _ in
            throw APIError.httpError(
                statusCode: 401,
                message: "Please confirm your email before signing in.",
                data: errorBody
            )
        }
        viewModel.openEmailForm()
        viewModel.email = "jane@example.com"
        viewModel.password = "testpass123"

        await viewModel.submitEmailForm()

        #expect(viewModel.formError == "Please confirm your email before signing in.")
        #expect(viewModel.pendingConfirmationEmail == "jane@example.com")
    }

    @Test("resend confirmation reports success")
    func resendConfirmation() async {
        let (viewModel, client) = makeViewModel()
        client.handlers["POST /api/auth/native/email/resend-confirmation"] = { _ in
            Data(#"{"success":true}"#.utf8)
        }
        viewModel.pendingConfirmationEmail = "jane@example.com"
        viewModel.email = "jane@example.com"

        await viewModel.resendConfirmationEmail()

        #expect(viewModel.successMessage == "Confirmation email sent.")
        #expect(viewModel.formError == nil)
    }

    // No network stub: if the mismatch guard failed, MockAPIClient would throw
    // .missingHandler and surface it in formError.
    @Test("resend is dropped when the email field no longer matches")
    func resendDroppedOnEditedEmail() async {
        let (viewModel, _) = makeViewModel()
        viewModel.pendingConfirmationEmail = "jane@example.com"
        viewModel.email = "someone-else@example.com"

        await viewModel.resendConfirmationEmail()

        #expect(viewModel.pendingConfirmationEmail == nil)
        #expect(viewModel.successMessage == nil)
        #expect(viewModel.formError == nil)
    }

    // MARK: - Reset

    @Test("reset request shows the non-committal success message and stays in reset mode")
    func resetRequestSuccess() async {
        let (viewModel, client) = makeViewModel()
        client.handlers["POST /api/auth/email/reset-password"] = { _ in
            Data(#"{"success":true}"#.utf8)
        }
        viewModel.openEmailForm()
        viewModel.switchMode(.reset)
        viewModel.email = "jane@example.com"

        await viewModel.submitEmailForm()

        #expect(viewModel.formMode == .reset)
        #expect(viewModel.successMessage == "If an account exists with that email, a reset link has been sent.")
    }
}
