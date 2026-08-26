import SwiftUI

struct AuthView: View {
    @State private var viewModel: AuthViewModel

    private enum EmailField: Hashable {
        case name, email, password
    }
    @FocusState private var focusedField: EmailField?

    init(viewModel: AuthViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // .all (container + keyboard) so the artwork and scrim stay put
            // when the keyboard rises — only the form should ride up.
            Image("Login")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .offset(x: -45)
                .ignoresSafeArea(.all)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 360)
            }
            .ignoresSafeArea(.all)
            .allowsHitTesting(false)

            Group {
                if viewModel.formMode == .providers {
                    providerButtons
                        .transition(.opacity)
                } else {
                    emailForm
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 16)
            .animation(.default, value: viewModel.formMode)
        }
        .alert("Sign In Failed", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.error = nil }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An unknown error occurred.")
        }
    }

    // MARK: - Providers

    private var providerButtons: some View {
        VStack(spacing: 16) {
            SignInWithAppleButton(
                onCredential: { credential in
                    Task { await viewModel.handleAppleCredential(credential) }
                },
                onError: { error in
                    viewModel.handleAuthorizationError(error)
                }
            )
            .frame(height: 50)
            .padding(.horizontal, 32)
            .disabled(viewModel.isLoading)

            SignInWithGoogleButton(
                onIDToken: { token in
                    Task { await viewModel.handleGoogleIDToken(token) }
                },
                onError: { error in
                    viewModel.handleGoogleError(error)
                }
            )
            .frame(height: 50)
            .padding(.horizontal, 32)
            .disabled(viewModel.isLoading)

            Button("Continue with email") {
                viewModel.openEmailForm()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .disabled(viewModel.isLoading)

            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    // MARK: - Email Form

    private var emailForm: some View {
        // ScrollView so sign-up mode stays reachable on small screens with the
        // keyboard up; bottom anchor keeps short content pinned to the bottom
        // like the provider stack.
        ScrollView {
            VStack(spacing: 12) {
                formMessages

                if viewModel.formMode == .signUp {
                    styledField {
                        TextField("Name (optional)", text: $viewModel.name, prompt: placeholder("Name (optional)"))
                            .textContentType(.name)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }
                    }
                }

                styledField {
                    TextField("Email", text: $viewModel.email, prompt: placeholder("Email"))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(viewModel.formMode == .reset ? .go : .next)
                        .onSubmit {
                            if viewModel.formMode == .reset {
                                Task { await viewModel.submitEmailForm() }
                            } else {
                                focusedField = .password
                            }
                        }
                }

                if viewModel.formMode != .reset {
                    styledField {
                        SecureField("Password", text: $viewModel.password, prompt: placeholder("Password"))
                            .textContentType(viewModel.formMode == .signUp ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit {
                                Task { await viewModel.submitEmailForm() }
                            }
                    }
                }

                if viewModel.formMode == .signIn {
                    Button("Forgot password?") {
                        viewModel.switchMode(.reset)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                submitButton

                HStack {
                    Button("Back") {
                        focusedField = nil
                        viewModel.closeEmailForm()
                    }
                    Spacer()
                    if viewModel.formMode == .signIn {
                        Button("Create an account") {
                            viewModel.switchMode(.signUp)
                        }
                    } else {
                        Button("Sign in instead") {
                            viewModel.switchMode(.signIn)
                        }
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .disabled(viewModel.isLoading)
        }
        .defaultScrollAnchor(.bottom)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var formMessages: some View {
        if let successMessage = viewModel.successMessage {
            Text(successMessage)
                .font(.footnote)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let formError = viewModel.formError {
            Text(formError)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if viewModel.pendingConfirmationEmail != nil {
            Button("Resend confirmation email") {
                Task { await viewModel.resendConfirmationEmail() }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var submitButton: some View {
        Button {
            focusedField = nil
            Task { await viewModel.submitEmailForm() }
        } label: {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text(submitTitle)
                }
            }
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white)
            )
        }
    }

    private var submitTitle: String {
        switch viewModel.formMode {
        case .signUp: return "Create Account"
        case .reset: return "Send Reset Link"
        default: return "Sign In"
        }
    }

    /// Placeholder text for the form fields. The default placeholder gray
    /// sinks into the near-black field fill; half-strength white keeps it
    /// legible while staying clearly secondary to typed (full-white) text.
    private func placeholder(_ label: String) -> Text {
        Text(label).foregroundStyle(.white.opacity(0.5))
    }

    /// Shared 50pt field chrome — same dark ground as the provider pills, with
    /// a fainter hairline so fields read as inputs rather than buttons. A
    /// translucent white fill washed out against the artwork; a solid dark
    /// fill is what keeps the fields legible over the bright parts of the image.
    private func styledField(@ViewBuilder content: () -> some View) -> some View {
        content()
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
            )
    }
}
