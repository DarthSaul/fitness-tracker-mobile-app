import SwiftUI
import AuthenticationServices

// MARK: - UIViewRepresentable Wrapper
struct SignInWithAppleButton: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled

    var onCredential: (ASAuthorizationAppleIDCredential) -> Void
    var onError: (any Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCredential: onCredential, onError: onError)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.cornerRadius = 8
        button.layer.cornerRadius = 8
        button.layer.borderColor = UIColor.white.cgColor
        button.layer.borderWidth = 1
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleTap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.isEnabled = isEnabled
    }
}

// MARK: - Coordinator
extension SignInWithAppleButton {
    final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        private let onCredential: (ASAuthorizationAppleIDCredential) -> Void
        private let onError: (any Error) -> Void

        init(onCredential: @escaping (ASAuthorizationAppleIDCredential) -> Void, onError: @escaping (any Error) -> Void) {
            self.onCredential = onCredential
            self.onError = onError
        }

        @objc func handleTap() {
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        // MARK: - ASAuthorizationControllerDelegate
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            onCredential(credential)
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
            onError(error)
        }

        // MARK: - ASAuthorizationControllerPresentationContextProviding
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            // Safe: called on main thread by the framework
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? UIWindow()
        }
    }
}
