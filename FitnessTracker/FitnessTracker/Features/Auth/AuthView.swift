import SwiftUI

struct AuthView: View {
    @State private var viewModel: AuthViewModel

    init(viewModel: AuthViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 48) {
                Spacer()

                // MARK: - Branding
                VStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 64))
                        .foregroundStyle(.primary)

                    Text("Fitness Tracker")
                        .font(.largeTitle.bold())

                    Text("Track every rep. Own your progress.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // MARK: - Sign In
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

                    if viewModel.isLoading {
                        ProgressView()
                    }
                }
                .padding(.bottom, 48)
            }
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
}
