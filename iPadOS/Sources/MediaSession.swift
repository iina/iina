// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import AVFoundation
import MediaPlayer
import UIKit

/// One media session owns the audio session, lock-screen metadata, and remote commands.
/// Notification/command callbacks may arrive off the main thread.
@MainActor
final class MediaSession {
    private weak var player: PlayerModel?
    private var commands: [(MPRemoteCommand, Any)] = []
    private var notifications: [NSObjectProtocol] = []
    private var interruptedMedia: UUID?
    private var lastMetadataUpdate = Date.distantPast
    private var audioActive = false
    private let artwork = UIImage(named: "IINALogo").map { image in
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    init(player: PlayerModel) {
        self.player = player
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { $0.setPaused(false) }
        register(center.pauseCommand) { $0.setPaused(true) }
        register(center.togglePlayPauseCommand) { $0.togglePause() }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        register(center.skipForwardCommand) { $0.skip(10) }
        register(center.skipBackwardCommand) { $0.skip(-10) }
        let seekToken = center.changePlaybackPositionCommand.addTarget { [weak player] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in player?.seek(to: position) }
            return .success
        }
        commands.append((center.changePlaybackPositionCommand, seekToken))
        center.changePlaybackRateCommand.supportedPlaybackRates = PlaybackRates.presets.map { NSNumber(value: $0) }
        let rateToken = center.changePlaybackRateCommand.addTarget { [weak player] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = Double(event.playbackRate)
            Task { @MainActor in player?.setSpeed(rate) }
            return .success
        }
        commands.append((center.changePlaybackRateCommand, rateToken))

        let audio = AVAudioSession.sharedInstance()
        notifications.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: audio, queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor in self?.interruption(type: type, options: options) }
        })
        notifications.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: audio, queue: .main
        ) { [weak player] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in player?.setPaused(true) }
            }
        })
        update(force: true)
    }

    private func register(_ command: MPRemoteCommand, perform: @escaping @MainActor (PlayerModel) -> Void) {
        let token = command.addTarget { [weak player] _ in
            guard let player else { return .commandFailed }
            Task { @MainActor in perform(player) }
            return .success
        }
        commands.append((command, token))
    }

    func activate() throws {
        guard !audioActive else { return }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try audio.setActive(true)
        audioActive = true
    }

    func cancelInterruptionResume() { interruptedMedia = nil }

    private func interruption(type: UInt?, options: UInt) {
        guard let player, let type, let kind = AVAudioSession.InterruptionType(rawValue: type) else { return }
        if kind == .began {
            interruptedMedia = player.paused ? nil : player.currentID
            player.setPaused(true, userInitiated: false)
            audioActive = false
        } else {
            let media = interruptedMedia
            interruptedMedia = nil
            if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume),
               media != nil, media == player.currentID {
                player.setPaused(false, userInitiated: false)
            }
        }
    }

    func update(force: Bool = false) {
        guard let player else { return }
        guard force || Date().timeIntervalSince(lastMetadataUpdate) >= 1 else { return }
        lastMetadataUpdate = Date()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = player.hasMedia
        center.pauseCommand.isEnabled = player.hasMedia
        center.togglePlayPauseCommand.isEnabled = player.hasMedia
        center.nextTrackCommand.isEnabled = player.canGoForward
        center.previousTrackCommand.isEnabled = player.canGoBack
        center.skipForwardCommand.isEnabled = player.duration > 0
        center.skipBackwardCommand.isEnabled = player.duration > 0
        center.changePlaybackPositionCommand.isEnabled = player.duration > 0
        center.changePlaybackRateCommand.isEnabled = player.hasMedia
        guard player.hasMedia else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: player.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position,
            MPNowPlayingInfoPropertyPlaybackRate: player.paused ? 0 : player.speed,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1,
            MPNowPlayingInfoPropertyMediaType: player.isAudioOnly ? MPNowPlayingInfoMediaType.audio.rawValue : MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: player.duration <= 0
        ]
        if player.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = player.duration }
        if !player.artist.isEmpty { info[MPMediaItemPropertyArtist] = player.artist }
        if !player.album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = player.album }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    deinit {
        commands.forEach { $0.0.removeTarget($0.1) }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
