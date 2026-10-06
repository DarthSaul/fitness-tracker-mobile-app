import SwiftUI

/// Account / preferences tab. Layout: profile header (Edit Profile + View
/// Profile) → Social → Preferences (appearance + feedback) → Sign Out →
/// About → Danger (Delete Account). The profile
/// header pulls from `SessionManager.userProfile`, which is populated by
/// GET /api/auth/me on bootstrap and after sign-in. The hosting tab provides
/// the NavigationStack.
struct SettingsView: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SocialContext.self) private var socialContext
    @Environment(NotificationCenterModel.self) private var notifications

    @AppStorage(appAppearanceStorageKey) private var appearanceRaw: String = AppAppearance.system.rawValue

    @State private var isSigningOut = false
    @State private var isDeletingAccount = false
    @State private var showDeleteConfirmation = false
    @State private var deleteAccountError: APIError?
    @State private var social: SocialSettingsViewModel?
    @State private var confirmGoPublic = false

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

            Section {
                NavigationLink {
                    EditProfileView(context: socialContext)
                } label: {
                    ProfileHeader(profile: sessionManager.userProfile)
                }
                // The separator would otherwise start at the name, past the
                // avatar. Start it at the row's content edge instead, where
                // the text-only rows below (Social) start theirs.
                .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }

                // The stack registers `.friendsDestinations()`, so this opens
                // the same profile screen others see (with my posts).
                if let userId = socialContext.currentUserId {
                    NavigationLink(value: FriendsRoute.profile(userId: userId)) {
                        Label("View Profile", systemImage: "person.crop.circle")
                    }
                }
            }

            if let social {
                socialSection(social)
            }

            Section("Preferences") {
                Picker(selection: appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }

                NavigationLink {
                    NotificationPreferencesView(repository: notifications.repository, context: socialContext)
                } label: {
                    Label("Notifications", systemImage: "bell.badge")
                }

                NavigationLink {
                    FeedbackView(viewModel: FeedbackViewModel(
                        repository: FeedbackRepository(apiClient: apiClient)
                    ))
                } label: {
                    Label("Feedback", systemImage: "bubble.left.and.bubble.right")
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
                .disabled(isSigningOut || isDeletingAccount)
            }

            Section("About") {
                LabeledContent("Version", value: AppVersion.displayString)
            }

            // Own section, below About, so the most dangerous action in the
            // app isn't one row away from a routine one.
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
                .confirmationAlert(
                    "Delete your account?",
                    isPresented: $showDeleteConfirmation,
                    message: "This permanently deletes your account and all of your data, including your entire workout history. This cannot be undone.",
                    confirmLabel: "Delete Account",
                    confirmRole: .destructive
                ) {
                    Task { await performDeleteAccount() }
                }
            } header: {
                Text("Danger")
            } footer: {
                Text("Deleting your account removes all of your data from our servers.")
            }
        }
        // Match the Home tab's 12pt padding above the in-flow title; the
        // default grouped-list top inset is otherwise inconsistent.
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollingTitleChrome(title: "Settings")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if social == nil { social = SocialSettingsViewModel(context: socialContext) }
            await social?.loadCounts()
        }
        .confirmationAlert(
            "Make your account public?",
            isPresented: $confirmGoPublic,
            message: goPublicMessage,
            confirmLabel: "Make Public"
        ) {
            Task { await social?.setPrivate(false) }
        }
        .alert("Couldn't Delete Account", isPresented: deleteErrorBinding) {
            Button("Retry") { Task { await performDeleteAccount() } }
            Button("Cancel", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError?.localizedDescription ?? "")
        }
    }

    // MARK: - Social

    private func socialSection(_ social: SocialSettingsViewModel) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { social.isPrivate },
                set: { makePrivate in
                    if makePrivate {
                        Task { await social.setPrivate(true) }
                    } else {
                        // Going public approves pending requests: warn first.
                        confirmGoPublic = true
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Private account")
                    Text("Approve who can follow you")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(social.isSaving(\UserProfile.profileVisibility))

            Toggle(isOn: Binding(
                get: { social.showActiveProgram },
                set: { value in Task { await social.setShowActiveProgram(value) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show current program")
                    Text("Its name, on your profile")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(social.isSaving(\UserProfile.showActiveProgram))

            Toggle(isOn: Binding(
                get: { social.showWorkoutCount },
                set: { value in Task { await social.setShowWorkoutCount(value) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show workout count")
                    Text("Total completed, on your profile")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(social.isSaving(\UserProfile.showWorkoutCount))

            NavigationLink {
                BlockedAccountsView(context: socialContext) { social.setBlockedCount($0) }
            } label: {
                LabeledContent("Blocked accounts") {
                    if let count = social.blockedCount { Text("\(count)") }
                }
            }
        } header: {
            Text("Social")
        } footer: {
            Text("Your workouts are only ever yours. Posts, and the two profile stats above, are what others can see.")
        }
        .tint(.green)
    }

    private var goPublicMessage: String {
        let pending = social?.pendingRequestCount ?? 0
        let approval = pending > 0
            ? " Your \(pending) pending request\(pending == 1 ? "" : "s") will be approved."
            : ""
        return "Anyone will be able to follow you and see your posts without asking.\(approval)"
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
        // User-initiated: revoke the refresh token and this phone's push
        // token server-side, then clear local state.
        await sessionManager.signOutByUser()
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
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 20, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
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

    /// "@saulg", falling back to the email before the username loads.
    private var subtitle: String? {
        guard let profile else { return nil }
        guard let username = profile.username else { return profile.email }
        return "@\(username)"
    }

    private var displayName: String {
        if let name = profile?.name, !name.isEmpty { return name }
        if let email = profile?.email { return email }
        return "Signed in"
    }

    /// The same hue-tinted avatar other people see on my posts.
    private var avatar: some View {
        InitialsAvatar(
            seed: profile?.id ?? "",
            name: profile?.name,
            fallback: profile?.username ?? profile?.email ?? "·",
            imageURL: profile?.avatarUrl.flatMap(URL.init(string:)),
            size: 56
        )
    }
}
