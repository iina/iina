// Copyright © 2026 IINA contributors. Licensed under GPLv3.

import AVFoundation
import GroupActivities

struct IINAWatchActivity: GroupActivity {
  static var activityIdentifier: String {
    Bundle.main.object(forInfoDictionaryKey: "WatchTogetherActivityIdentifier") as? String ?? "com.colliderli.iina.watch-video"
  }
  let media: SharePlayMedia

  var metadata: GroupActivityMetadata {
    var metadata = GroupActivityMetadata()
    metadata.title = media.title
    metadata.type = .watchTogether
    return metadata
  }
}

/// Delegate entry points may run on arbitrary queues; all mutable state is confined to main.
final class SharePlayCoordinator: NSObject, SharePlayCoordinating, AVPlaybackCoordinatorPlaybackControlDelegate, @unchecked Sendable {
  weak var playback: SharePlayPlayback?
  private(set) lazy var coordinator = AVDelegatingPlaybackCoordinator(playbackControlDelegate: self)
  private var suspensions: [SharePlaySuspension: AVCoordinatedPlaybackSuspension] = [:]

  static var hostTime: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

  func connect(to session: GroupSession<IINAWatchActivity>, position: Double, rate: Double) -> Bool {
    guard prepare(position: position, rate: rate) else { return false }
    coordinator.coordinateWithSession(session)
    return true
  }

  @discardableResult
  func prepare(position: Double, rate: Double) -> Bool {
    guard let playback, position.isFinite, position >= 0, rate.isFinite, rate >= 0, rate <= 100 else { return false }
    var timebase: CMTimebase?
    let status = CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                                sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
    guard status == noErr, let timebase,
          CMTimebaseSetTime(timebase, time: CMTime(seconds: position, preferredTimescale: 60000)) == noErr,
          CMTimebaseSetRate(timebase, rate: rate) == noErr else { return false }
    coordinator.transitionToItem(withIdentifier: playback.media.id.uuidString,
                                 proposingInitialTimingBasedOn: timebase)
    return true
  }

  func disconnect() {
    playback = nil
    coordinator.transitionToItem(withIdentifier: nil, proposingInitialTimingBasedOn: nil)
    // Releasing this bridge after leaving the GroupSession disconnects its coordinator.
    suspensions.removeAll()
  }

  func coordinate(rate: Double) { coordinator.coordinateRateChange(to: Float(rate), options: []) }
  func coordinate(seek: Double) { coordinator.coordinateSeek(to: CMTime(seconds: seek, preferredTimescale: 60000), options: []) }
  func resynchronize() { coordinator.reapplyCurrentItemStateToPlaybackControlDelegate() }
  func expectedPosition(at hostTime: Double) -> Double? {
    let time = coordinator.expectedItemTime(atHostTime: CMTime(seconds: hostTime, preferredTimescale: 1000000000))
    return time.isNumeric ? time.seconds : nil
  }

  func suspend(_ reason: SharePlaySuspension) {
    guard suspensions[reason] == nil else { return }
    let nativeReason: AVCoordinatedPlaybackSuspension.Reason
    switch reason {
    case .buffering: nativeReason = .stallRecovery
    case .system: nativeReason = .audioSessionInterrupted
    case .automation: nativeReason = .userActionRequired
    }
    suspensions[reason] = coordinator.beginSuspension(for: nativeReason)
  }

  func resume(_ reason: SharePlaySuspension) { suspensions.removeValue(forKey: reason)?.end() }

  func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator,
                           didIssue command: AVDelegatingPlaybackCoordinatorPlayCommand,
                           completionHandler: @escaping @Sendable () -> Void) {
    deliver(item: command.expectedCurrentItemIdentifier, completion: completionHandler) { item in
      .play(item: item, time: command.itemTime.seconds, hostTime: command.hostClockTime.seconds, rate: Double(command.rate))
    }
  }

  func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator,
                           didIssue command: AVDelegatingPlaybackCoordinatorPauseCommand,
                           completionHandler: @escaping @Sendable () -> Void) {
    deliver(item: command.expectedCurrentItemIdentifier, completion: completionHandler) { item in
      .pause(item: item, buffering: command.shouldBufferInAnticipationOfPlayback)
    }
  }

  func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator,
                           didIssue command: AVDelegatingPlaybackCoordinatorSeekCommand,
                           completionHandler: @escaping @Sendable () -> Void) {
    deliver(item: command.expectedCurrentItemIdentifier, maximumWait: command.completionDueDate?.timeIntervalSinceNow,
            completion: completionHandler) { item in
      .seek(item: item, time: command.itemTime.seconds)
    }
  }

  func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator,
                           didIssue command: AVDelegatingPlaybackCoordinatorBufferingCommand,
                           completionHandler: @escaping @Sendable () -> Void) {
    deliver(item: command.expectedCurrentItemIdentifier, maximumWait: command.completionDueDate?.timeIntervalSinceNow,
            completion: completionHandler) { .buffer(item: $0) }
  }

  private func deliver(item: String, maximumWait: Double? = nil, completion: @escaping () -> Void,
                       command: @escaping (UUID) -> SharePlayPlayback.Command) {
    DispatchQueue.main.async { [weak self] in
      guard let playback = self?.playback, let id = UUID(uuidString: item) else { completion(); return }
      playback.receive(command(id), maximumWait: maximumWait ?? 8, completion: completion)
    }
  }
}
