import SwiftUI

/// A post's photos full screen, on black, each shown whole at its own
/// shape (never cropped). Swipe between photos, pinch or double-tap to zoom,
/// swipe down or tap ✕ to close. Opened by tapping a photo on a post card.
struct PostPhotoViewer: View {
    let photos: [PostPhotoDTO]

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String
    /// How far the current photo is being dragged down to close; fades the
    /// backdrop as it grows.
    @State private var dismissOffset: CGFloat = 0

    init(photos: [PostPhotoDTO], initialIndex: Int) {
        self.photos = photos
        let index = photos.indices.contains(initialIndex) ? initialIndex : 0
        _selection = State(initialValue: photos.isEmpty ? "" : photos[index].id)
    }

    private var currentIndex: Int {
        photos.firstIndex { $0.id == selection } ?? 0
    }

    private var backdropOpacity: Double {
        1 - min(abs(dismissOffset) / 400, 0.6)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(photos) { photo in
                ZoomablePhoto(
                    photo: photo,
                    isCurrent: photo.id == selection,
                    dismissOffset: $dismissOffset,
                    onDismiss: { dismiss() }
                )
                .tag(photo.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
        .background(Color.black.opacity(backdropOpacity).ignoresSafeArea())
        .overlay(alignment: .top) { topBar }
        .statusBarHidden()
        .presentationBackground(.clear)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer()

            if photos.count > 1 {
                Text("\(currentIndex + 1) of \(photos.count)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .opacity(dismissOffset == 0 ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: dismissOffset == 0)
    }
}

/// One page of the viewer. At 1× a vertical drag moves the photo to close
/// the viewer; zoomed in, a drag pans instead (and paging waits until the
/// photo is back at 1×).
private struct ZoomablePhoto: View {
    let photo: PostPhotoDTO
    let isCurrent: Bool
    @Binding var dismissOffset: CGFloat
    let onDismiss: () -> Void

    private static let maxScale: CGFloat = 4
    private static let doubleTapScale: CGFloat = 2.5
    private static let dismissThreshold: CGFloat = 120

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragDown: CGFloat = 0

    private var isZoomed: Bool { scale > 1.01 }

    var body: some View {
        GeometryReader { proxy in
            image
                .scaleEffect(scale)
                .offset(x: offset.width, y: offset.height + dragDown)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { toggleZoom() }
                .simultaneousGesture(magnify)
                .gesture(pan(in: proxy.size), including: isZoomed ? .all : .subviews)
                .simultaneousGesture(dismissDrag, including: isZoomed ? .subviews : .all)
        }
        .onChange(of: isCurrent) { _, current in
            if !current { resetZoom(animated: false) }
        }
        // Zooming disables the dismiss drag, whose onEnded may then never
        // fire — undo any pull-down already in progress.
        .onChange(of: isZoomed) { _, zoomed in
            guard zoomed, dragDown != 0 || dismissOffset != 0 else { return }
            withAnimation(.spring(duration: 0.3)) {
                dragDown = 0
                dismissOffset = 0
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Photo")
        .accessibilityAddTraits(.isImage)
    }

    private var image: some View {
        AsyncImage(url: URL(string: photo.url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                placeholder {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.6))
                }
            default:
                placeholder { ProgressView().tint(.white) }
            }
        }
        .id(photo.id)
    }

    /// Reserves the photo's own shape while it loads or if it fails.
    private func placeholder(@ViewBuilder _ content: () -> some View) -> some View {
        Color.white.opacity(0.06)
            .aspectRatio(photo.aspectRatio, contentMode: .fit)
            .overlay { content() }
    }

    // MARK: Gestures

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), Self.maxScale)
            }
            .onEnded { _ in
                if scale <= 1.01 {
                    resetZoom(animated: true)
                } else {
                    lastScale = scale
                }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                ), in: size)
            }
            .onEnded { _ in lastOffset = offset }
    }

    /// Only acts on mostly-vertical drags, so horizontal swipes still page.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isZoomed else { return }
                let t = value.translation
                guard dragDown != 0 || abs(t.height) > abs(t.width) else { return }
                dragDown = t.height
                dismissOffset = t.height
            }
            .onEnded { value in
                guard dragDown != 0 else { return }
                if abs(value.translation.height) > Self.dismissThreshold
                    || abs(value.predictedEndTranslation.height) > Self.dismissThreshold * 2.5 {
                    onDismiss()
                } else {
                    withAnimation(.spring(duration: 0.3)) {
                        dragDown = 0
                        dismissOffset = 0
                    }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(duration: 0.3)) {
            if isZoomed {
                resetZoom(animated: false)
            } else {
                scale = Self.doubleTapScale
                lastScale = Self.doubleTapScale
            }
        }
    }

    private func resetZoom(animated: Bool) {
        let reset = {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
        if animated {
            withAnimation(.spring(duration: 0.3), reset)
        } else {
            reset()
        }
    }

    /// Keeps a zoomed photo from being panned past its edges.
    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}
