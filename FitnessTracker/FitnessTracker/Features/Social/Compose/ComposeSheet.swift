import PhotosUI
import SwiftUI

/// New Post sheet (design-spec 04). Opens at 420pt and grows to full height
/// while typing. There's no per-post audience: the footer states who sees
/// it, which follows the profile's privacy.
struct ComposeSheet: View {
    @State private var viewModel: ComposeViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
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
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickerItems,
            maxSelectionCount: max(viewModel.remainingPhotoSlots, 1),
            matching: .images
        )
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task {
                var data: [Data] = []
                for item in items {
                    if let loaded = try? await item.loadTransferable(type: Data.self) { data.append(loaded) }
                }
                await viewModel.addPhotos(data)
            }
        }
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
                    SocialStyle.brandGradient.frame(width: 4)
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
                .background(SocialStyle.embed)
                .clipShape(RoundedRectangle(cornerRadius: SocialStyle.embedRadius, style: .continuous))
                removeButton(label: "Remove workout") { viewModel.workout = nil }
                    .padding(8)
            }
            .padding(.leading, 52)
        }

        if !viewModel.photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.photos) { photo in
                        photoThumb(photo)
                    }
                }
            }
            .padding(.leading, 52)
        }
    }

    private func photoThumb(_ photo: ComposeViewModel.AttachedPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = photo.preview {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    SocialStyle.embed
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                switch photo.state {
                case .processing, .uploading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                case .uploaded:
                    EmptyView()
                }
            }
            removeButton(label: "Remove photo") { viewModel.removePhoto(photo.id) }
                .padding(4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(photoAccessibilityLabel(photo.state))
    }

    private func photoAccessibilityLabel(_ state: ComposeViewModel.AttachedPhoto.State) -> String {
        switch state {
        case .processing, .uploading: "Photo, uploading"
        case .uploaded: "Photo"
        case .failed(let message): "Photo failed to upload. \(message)"
        }
    }

    private func removeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color(.systemGray2), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
