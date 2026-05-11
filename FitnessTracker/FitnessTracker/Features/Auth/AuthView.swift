import SwiftUI

struct AuthView: View {
    @State private var viewModel: AuthViewModel

    init(viewModel: AuthViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("Login")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .offset(x: -45)
                .ignoresSafeArea()
                .accessibilityLabel("Fitness Tracker")

            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 360)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

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
                        .tint(.white)
                }
            }
            .padding(.bottom, 16)
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
