import SwiftUI

/// Edit Profile (not mocked; standard grouped form): username and bio.
struct EditProfileView: View {
    @State private var viewModel: EditProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionManager.self) private var sessionManager

    init(context: SocialContext) {
        _viewModel = State(initialValue: EditProfileViewModel(context: context))
    }

    var body: some View {
        Form {
            if let profile = sessionManager.userProfile {
                Section {
                    HStack(spacing: 14) {
                        InitialsAvatar(
                            seed: profile.id,
                            name: profile.name,
                            fallback: profile.username ?? profile.email,
                            imageURL: profile.avatarUrl.flatMap(URL.init(string:)),
                            size: 56
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name?.isEmpty == false ? profile.name! : "No name")
                                .font(.headline)
                            Text("Name and photo come from your sign-in account.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(.secondary)
                    TextField("username", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    if viewModel.usernameStatus == .checking {
                        ProgressView().controlSize(.small)
                    } else if viewModel.usernameStatus == .available {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Username")
            } footer: {
                if let message = viewModel.usernameMessage {
                    Text(message).foregroundStyle(viewModel.usernameStatus == .available ? Color.secondary : Color.red)
                }
            }

            Section {
                TextField("A line about you", text: $viewModel.bio, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Bio")
            } footer: {
                HStack {
                    Text("Shown on your profile to anyone who can see it.")
                    Spacer()
                    Text("\(viewModel.bioLength)/\(SocialRules.bioMax)")
                        .monospacedDigit()
                        .foregroundStyle(viewModel.isBioTooLong ? Color.red : Color.secondary)
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { if await viewModel.save() { dismiss() } }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
        .onChange(of: viewModel.username) { viewModel.usernameEdited() }
        .sensoryFeedback(.success, trigger: viewModel.didSave)
    }
}
