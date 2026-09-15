import SwiftUI

/// Slide-up demo for one exercise: fetches GET /api/exercises/:id/info and
/// loops the animation clip with the poster frame shown until the first video
/// frame renders. Always re-fetches on open — the media URLs are signed and
/// expire after ~15 minutes, so nothing here is cached.
///
/// License constraints for the clips: inline playback only, no share /
/// download / AirPlay affordances, and no disk caching (the poster is loaded
/// through an ephemeral session for that reason).
struct ExerciseDemoSheet: View {
    let exerciseId: String
    let exerciseName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var apiClient

    @State private var info: ExerciseInfoDTO?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isVideoReady = false
    @State private var playbackError: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(exerciseName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && info == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView(
                "Couldn't load demo",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
        } else if let playbackError {
            ContentUnavailableView(
                "Couldn't play demo",
                systemImage: "video.slash",
                description: Text(playbackError)
            )
        } else if let info, let url = info.animationURL {
            player(url: url, posterURL: info.posterURL)
        } else {
            ContentUnavailableView(
                "No demo yet",
                systemImage: "video.slash",
                description: Text("Sorry, we don't have a demo for this exercise just yet.")
            )
        }
    }

    private func player(url: URL, posterURL: URL?) -> some View {
        ZStack {
            LoopingVideoPlayerView(
                url: url,
                isReadyForDisplay: $isVideoReady,
                onFailure: { playbackError = $0 }
            )
            if !isVideoReady {
                PosterImage(url: posterURL)
                    .transition(.opacity)
            }
        }
        // Clips are 720×720.
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: isVideoReady)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let dto: ExerciseInfoDTO = try await apiClient.send(.getExerciseInfo(exerciseId: exerciseId))
            info = dto
        } catch APIError.httpError(statusCode: 404, _, _) {
            // Unknown exercise reads the same as "no media" to the user.
            info = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Poster frame shown while the video buffers. Loads through an ephemeral
/// (memory-only) session rather than `AsyncImage`, which routes through the
/// disk-backed shared `URLCache` — the media license forbids caching to disk.
/// `UIImage(data:)` decodes WebP natively on iOS 14+.
private struct PosterImage: View {
    let url: URL?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(uiColor: .secondarySystemBackground)
                    .overlay { ProgressView() }
            }
        }
        .task(id: url) {
            guard let url else { return }
            let session = URLSession(configuration: .ephemeral)
            if let (data, _) = try? await session.data(from: url) {
                image = UIImage(data: data)
            }
        }
    }
}
