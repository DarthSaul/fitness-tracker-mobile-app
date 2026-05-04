import SwiftUI

/// Account / sign-out sheet, presented as a modal from each tab's toolbar.
/// Web equivalent: SettingsDrawer (right-side slideover). On iOS we use a
/// sheet for native modal idiom rather than porting the drawer pattern.
struct SettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var isSigningOut = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if case .authenticated(let userId) = sessionManager.authState {
                        // User name / email / avatar arrive once we surface
                        // those on the auth response — see Backlog.
                        LabeledContent("User ID") {
                            Text(userId)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await performSignOut() }
                    } label: {
                        if isSigningOut {
                            HStack {
                                ProgressView()
                                Text("Signing out…")
                            }
                        } else {
                            Text("Sign Out")
                        }
                    }
                    .disabled(isSigningOut)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func performSignOut() async {
        isSigningOut = true
        await sessionManager.signOut()
        // SessionManager.authState flipping to .unauthenticated re-renders
        // ContentView back to AuthView; dismissing the sheet here is just
        // belt-and-suspenders cleanup.
        dismiss()
    }
}
