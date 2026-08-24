import SwiftUI

/// Account / preferences tab. Layout: profile header → Preferences
/// (appearance + feedback) → About → Sign Out → Delete Account. The profile
/// header pulls from `SessionManager.userProfile`, which is populated by
/// GET /api/auth/me on bootstrap and after sign-in. The hosting tab provides
/// the NavigationStack.
struct SettingsView: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager

    @AppStorage(appAppearanceStorageKey) private var appearanceRaw: String = AppAppearance.system.rawValue

    @State private var isSigningOut = false
    @State private var isDeletingAccount = false
    @State private var showDeleteConfirmation = false
    @State private var deleteAccountError: APIError?

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            // In-flow title styled as a plain full-bleed row so it lines up
            // with the other tabs' headers (its own padding provides the
            // horizontal inset).
            ScreenTitleHeader(title: "Settings", emoji: "⚙️")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Section { ProfileHeader(profile: sessionManager.userProfile) }

            Section("Preferences") {
                Picker(selection: appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }

                NavigationLink {
                    FeedbackView(viewModel: FeedbackViewModel(
                        repository: FeedbackRepository(apiClient: apiClient)
                    ))
                } label: {
                    Label("Feedback", systemImage: "bubble.left.and.bubble.right")
                }
            }

            Section("About") {
                LabeledContent("Version", value: AppVersion.displayString)
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
                .disabled(isSigningOut || isDeletingAccount)
            }

            // Own section (not sharing Sign Out's) so the most dangerous
            // action in the app isn't one row away from a routine one.
            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    if isDeletingAccount {
                        HStack {
                            ProgressView()
                            Text("Deleting Account…")
                        }
                    } else {
                        Text("Delete Account")
                    }
                }
                .disabled(isDeletingAccount || isSigningOut)
                .confirmationDialog(
                    "Delete your account?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete Account", role: .destructive) {
                        Task { await performDeleteAccount() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This permanently deletes your account and all of your data, including your entire workout history. This cannot be undone.")
                }
            } footer: {
                Text("Deleting your account removes all of your data from our servers.")
            }
        }
        // Match the Home tab's 12pt padding above the in-flow title; the
        // default grouped-list top inset is otherwise inconsistent.
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollingTitleChrome(title: "Settings")
        .toolbar(.hidden, for: .navigationBar)
        .alert("Couldn't Delete Account", isPresented: deleteErrorBinding) {
            Button("Retry") { Task { await performDeleteAccount() } }
            Button("Cancel", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError?.localizedDescription ?? "")
        }
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )
    }

    private func performSignOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        // Reset on every exit so the button doesn't stay disabled if signOut
        // returns without the view tearing down (e.g. an unforeseen error path).
        defer { isSigningOut = false }
        await sessionManager.signOut()
        // SessionManager.authState flipping to .unauthenticated swaps
        // ContentView back to AuthView, so no explicit dismissal is needed.
    }

    private func performDeleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        deleteAccountError = nil
        do {
            try await sessionManager.deleteAccount()
            // authState flipping to .unauthenticated swaps ContentView back
            // to AuthView — no explicit navigation needed.
        } catch APIError.unauthorized {
            // Token refresh failed mid-delete: the session is dead but the
            // account was NOT deleted. Fall back to a plain local sign-out
            // (the app-wide convention for a dead session) — the user lands
            // on sign-in with their account intact and can retry after
            // re-authenticating.
            await sessionManager.signOut()
        } catch {
            deleteAccountError = error
        }
    }
}

private struct ProfileHeader: View {
    let profile: UserProfile?

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                if let email = profile?.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        if let name = profile?.name, !name.isEmpty { return name }
        if let email = profile?.email { return email }
        return "Signed in"
    }

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            Circle().fill(Color.purple.opacity(0.15))
            Text(initials)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.purple)
        }
        .frame(width: 44, height: 44)
    }

    private var initials: String {
        let source: String? = profile?.name?.isEmpty == false ? profile?.name : profile?.email
        guard let s = source, !s.isEmpty else { return "·" }
        let parts = s.split(separator: " ", maxSplits: 1)
        if parts.count == 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(s.prefix(1)).uppercased()
    }
}
