import PhotosUI
import SwiftUI

/// The attached photos as a horizontal strip of 96pt thumbnails, each with
/// an upload overlay and a remove button. Shared by the New Post sheet and
/// the post-workout share prompt.
struct AttachedPhotoStrip: View {
    let attachments: PhotoAttachments

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments.photos) { photo in
                    thumb(photo)
                }
            }
        }
    }

    private func thumb(_ photo: PhotoAttachments.AttachedPhoto) -> some View {
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
            AttachmentRemoveButton(label: "Remove photo") { attachments.removePhoto(photo.id) }
                .padding(4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(photo.state))
    }

    private func accessibilityLabel(_ state: PhotoAttachments.AttachedPhoto.State) -> String {
        switch state {
        case .processing, .uploading: "Photo, uploading"
        case .uploaded: "Photo"
        case .failed(let message): "Photo failed to upload. \(message)"
        }
    }
}

/// The small gray ⓧ on an attachment's corner.
struct AttachmentRemoveButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
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
}

extension View {
    /// Presents the system photo picker and hands the picked images to
    /// `attachments`, up to its remaining slots.
    func photoAttachmentPicker(isPresented: Binding<Bool>, attachments: PhotoAttachments) -> some View {
        modifier(PhotoAttachmentPicker(isPresented: isPresented, attachments: attachments))
    }
}

private struct PhotoAttachmentPicker: ViewModifier {
    @Binding var isPresented: Bool
    let attachments: PhotoAttachments
    @State private var pickerItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $pickerItems,
                maxSelectionCount: max(attachments.remainingPhotoSlots, 1),
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
                    await attachments.addPhotos(data)
                }
            }
    }
}
