import SwiftUI

/// New Post sheet (design-spec 04). Opens at 420pt and grows to full height
/// while typing. There's no per-post audience: the footer states who sees
/// it, which follows the profile's privacy.
struct ComposeSheet: View {
    @State private var viewModel: ComposeViewModel
    @State private var showPhotoPicker: Bool
    @State private var detent: PresentationDetent = .height(420)
    @FocusState private var captionFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionManager.self) private var sessionManager

    init(context: SocialContext, workout: ComposeViewModel.AttachedWorkout? = nil, startWithPhotoPicker: Bool = false) {
        _viewModel = State(initialValue: ComposeViewModel(context: context, workout: workout))
        _showPhotoPicker = State(initialValue: startWithPhotoPicker)
    }

    var body: some View {
        VStack(spacing: 0) {
            navRow
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    captionRow
                    attachments
                    attachChips
                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.leading, 52)
                    }
                }
                .padding(16)
            }
            footer
        }
        .background(SocialStyle.card)
        .presentationDetents([.height(420), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(SocialStyle.cardRadius)
        .onChange(of: captionFocused) { _, focused in
            if focused { detent = .large }
        }
        .photoAttachmentPicker(isPresented: $showPhotoPicker, attachments: viewModel.photoAttachments)
        .sensoryFeedback(.success, trigger: viewModel.didPost)
        .interactiveDismissDisabled(viewModel.isPosting)
    }

    // MARK: Nav row

    private var navRow: some View {
        ZStack {
            Text("New Post").font(.system(size: 17, weight: .semibold))
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 17))
                Spacer()
                Button {
                    Task { if await viewModel.submit() { dismiss() } }
                } label: {
                    if viewModel.isPosting {
                        ProgressView().tint(.white).frame(width: 36)
                    } else {
                        Text("Post")
                    }
                }
                .buttonStyle(.pill(.blue, height: 32))
                .disabled(!viewModel.canSubmit)
                .opacity(viewModel.canSubmit ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    // MARK: Body

    private var captionRow: some View {
        HStack(alignment: .top, spacing: 12) {
            myAvatar
            TextField("Share an update…", text: $viewModel.caption, axis: .vertical)
                .font(.system(size: 17))
                .lineSpacing(4)
                .lineLimit(2...12)
                .focused($captionFocused)
        }
    }

    @ViewBuilder
    private var myAvatar: some View {
        if let profile = sessionManager.userProfile {
            InitialsAvatar(
                seed: profile.id,
                name: profile.name,
                fallback: profile.username ?? profile.email,
                imageURL: profile.avatarUrl.flatMap(URL.init(string:)),
                size: 40
            )
        } else {
            Circle().fill(SocialStyle.fill).frame(width: 40, height: 40)
        }
    }

    @ViewBuilder
    private var attachments: some View {
        if let workout = viewModel.workout {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sharing a completed workout")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(workout.label)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    Spacer(minLength: 30)
                }
                .leadingAccentBar()
                .background(SocialStyle.embed)
                .clipShape(RoundedRectangle(cornerRadius: SocialStyle.embedRadius, style: .continuous))
                AttachmentRemoveButton(label: "Remove workout") { viewModel.workout = nil }
                    .padding(8)
            }
            .padding(.leading, 52)
        }

        if !viewModel.photos.isEmpty {
            AttachedPhotoStrip(attachments: viewModel.photoAttachments)
                .padding(.leading, 52)
        }
    }

    private var attachChips: some View {
        HStack(spacing: 8) {
            Button {
                showPhotoPicker = true
            } label: {
                Label("Photo", systemImage: "photo")
            }
            .buttonStyle(.pill(.gray))
            .disabled(viewModel.remainingPhotoSlots == 0)
        }
        .padding(.leading, 52)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Label(audienceText, systemImage: "person.2.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(viewModel.captionLength) / \(ComposeViewModel.captionMax)")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(viewModel.isCaptionTooLong ? Color.red : SocialStyle.tertiaryText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
        }
    }

    /// Who will see it, from my profile's privacy (posts have no audience
    /// of their own).
    private var audienceText: String {
        sessionManager.userProfile?.profileVisibility == .public ? "Visible to everyone" : "Visible to your followers"
    }
}
