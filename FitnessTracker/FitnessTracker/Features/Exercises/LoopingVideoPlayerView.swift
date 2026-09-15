import AVFoundation
import SwiftUI

/// Chrome-less looping player: an `AVPlayerLayer` backed by `AVQueuePlayer` +
/// `AVPlayerLooper`. Deliberately NOT `VideoPlayer` / `AVPlayerViewController`
/// — the exercise-media license requires inline playback with no transport
/// controls, share sheet, AirPlay, or picture-in-picture. Muted (the clips have
/// no audio track) and `.ambient` so it never interrupts the user's music.
struct LoopingVideoPlayerView: UIViewRepresentable {
    let url: URL
    /// Flips to true once the first frame is on screen — the moment a poster
    /// overlay should fade out.
    @Binding var isReadyForDisplay: Bool
    var onFailure: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        let ready = $isReadyForDisplay
        return Coordinator(onReady: { ready.wrappedValue = true }, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        context.coordinator.attach(to: view.playerLayer, url: url)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        // Only rebuild the player graph on a real URL change (e.g. a re-fetch
        // that yields a freshly signed URL).
        if context.coordinator.currentURL != url {
            context.coordinator.attach(to: view.playerLayer, url: url)
        }
    }

    static func dismantleUIView(_ view: PlayerLayerView, coordinator: Coordinator) {
        coordinator.tearDown()
        view.playerLayer.player = nil
    }

    // MARK: - Layer-backed view

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    // MARK: - Coordinator owns the player graph

    /// Not `@MainActor`-annotated so it satisfies `UIViewRepresentable`'s
    /// requirements regardless of SDK isolation; every entry point is called
    /// from SwiftUI on the main thread, and the KVO callbacks hop back via
    /// `Task { @MainActor in … }` before touching the closures.
    final class Coordinator {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var readyObservation: NSKeyValueObservation?
        private var looperObservation: NSKeyValueObservation?
        private(set) var currentURL: URL?
        private let onReady: () -> Void
        private let onFailure: ((String) -> Void)?

        init(onReady: @escaping () -> Void, onFailure: ((String) -> Void)?) {
            self.onReady = onReady
            self.onFailure = onFailure
        }

        func attach(to layer: AVPlayerLayer, url: URL) {
            tearDown()
            // Silent demo clip: mix with (never interrupt) other audio and
            // respect the ring/silent switch. Cheap and idempotent, so it's set
            // here next to the only player rather than app-wide.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])

            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.allowsExternalPlayback = false // no AirPlay (license)
            let looper = AVPlayerLooper(player: player, templateItem: item)
            layer.player = player

            // Capture the callbacks, not `self`, so the KVO closures don't
            // retain the coordinator and the Task hop has no captured var.
            let onReady = self.onReady
            let onFailure = self.onFailure
            readyObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
                guard layer.isReadyForDisplay else { return }
                Task { @MainActor in onReady() }
            }
            looperObservation = looper.observe(\.status, options: [.new]) { looper, _ in
                guard looper.status == .failed else { return }
                let message = looper.error?.localizedDescription ?? "Playback failed."
                Task { @MainActor in onFailure?(message) }
            }

            self.player = player
            self.looper = looper
            self.currentURL = url
            player.play()
        }

        func tearDown() {
            readyObservation = nil
            looperObservation = nil
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player?.removeAllItems()
            player = nil
            currentURL = nil
        }
    }
}
