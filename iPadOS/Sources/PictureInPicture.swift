// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import AVKit
import Foundation

/// AVPlayer and mpv's sample-buffer output use the same native iPadOS PiP window.
@MainActor
final class PictureInPicture: NSObject, @preconcurrency AVPictureInPictureControllerDelegate, @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate {
    private weak var player: PlayerModel?
    // The sample-buffer source needs self as delegate, so assign once after super.init.
    private var controller: AVPictureInPictureController!
    private var possibleObservation: NSKeyValueObservation?

    init?(player: PlayerModel, surface: VideoSurfaceView, backend: PlaybackBackend) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return nil }
        self.player = player
        super.init()
        let source: AVPictureInPictureController.ContentSource
        if backend == .native {
            source = .init(playerLayer: surface.nativeLayer)
        } else {
            source = .init(sampleBufferDisplayLayer: surface.sampleLayer, playbackDelegate: self)
        }
        controller = AVPictureInPictureController(contentSource: source)
        configure()
    }

    private func configure() {
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.player?.pictureInPicturePossible = self.controller.isPictureInPicturePossible
            }
        }
    }

    func update() {
        controller.canStartPictureInPictureAutomaticallyFromInline = player?.musicMode == false
        controller.requiresLinearPlayback = (player?.duration ?? 0) <= 0
        controller.invalidatePlaybackState()
    }

    func start() {
        guard controller.isPictureInPicturePossible else {
            player?.report("Picture in Picture is not ready for this video yet."); return
        }
        controller.startPictureInPicture()
    }

    func stop() { controller.stopPictureInPicture() }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        player?.pictureInPictureWillStart()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        player?.pictureInPictureDidStart()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   failedToStartPictureInPictureWithError error: Error) {
        player?.pictureInPictureDidStop()
        player?.report("Unable to start Picture in Picture: \(error.localizedDescription)")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        player?.pictureInPictureDidStop()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(player != nil)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        player?.setPaused(!playing)
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        guard let player, player.hasMedia else { return .invalid }
        return CMTimeRange(start: .zero, duration: player.duration > 0
                           ? CMTime(seconds: player.duration, preferredTimescale: 600) : .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        player?.paused ?? true
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        player?.resizePictureInPicture(CGSize(width: Int(newRenderSize.width), height: Int(newRenderSize.height)))
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        guard let player else { completionHandler(); return }
        player.seek(to: player.position + skipInterval.seconds, completion: completionHandler)
    }

    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }
}
