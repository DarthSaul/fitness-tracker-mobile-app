import SwiftUI
import GoogleSignIn

struct SignInWithGoogleButton: View {
    @Environment(\.isEnabled) private var isEnabled

    var onIDToken: (String) -> Void
    var onError: (any Error) -> Void

    var body: some View {
        Button(action: signIn) {
            HStack(spacing: 8) {
                Text("G")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text("Sign in with Google")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white, lineWidth: 1)
            )
        }
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func signIn() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        GIDSignIn.sharedInstance.signIn(withPresenting: root) { result, error in
            if let error {
                onError(error)
                return
            }
            guard let idToken = result?.user.idToken?.tokenString else {
                onError(AuthError.missingIdentityToken)
                return
            }
            onIDToken(idToken)
        }
    }
}
