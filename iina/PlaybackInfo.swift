//
//  PlaybackInfo.swift
//  iina
//
//  Created by lhc on 21/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class PlaybackInfo {

  /// Enumeration representing the status of the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  ///
  /// The A-B loop command cycles mpv through these states:
  /// - Cleared (looping disabled)
  /// - A loop point set
  /// - B loop point set (looping enabled)
  enum LoopStatus {
    case cleared
    case aSet
    case bSet
  }

  enum MediaIsAudioStatus {
    case unknown
    case isAudio
    case notAudio
  }

  unowned let player: PlayerCore

  init(_ pc: PlayerCore) {
    player = pc
  }

  /// The state the `PlayerCore` is in.
  ///
  /// A computed property is used to prevent inappropriate state changes and perform actions based on the state changing. The
  /// following rules are enforced on state changes:
  /// - `loading` is not allowed to change to `idle`
  /// - `stopping` is only allowed to change to `idle`
  /// - `shuttingDown` is only allowed to change to `shutDown`
  /// - `shutDown` is not allowed to change to any other state
  var state: PlayerState = .idle {
    didSet {
      // Nothing to do if the old state matches the state that was just assigned.
      guard state != oldValue else { return }
      // Block inappropriate state changes.
      guard oldValue != .loading || state != .idle, oldValue != .stopping || state == .idle,
            oldValue != .shuttingDown || state == .shutDown, oldValue != .shutDown else {
        player.log("Blocked attempt to change state from \(oldValue) to \(state)", level: .verbose)
        state = oldValue
        return
      }
      player.log("State changed from \(oldValue) to \(state)", level: .verbose)
      switch state {
      case .idle:
        PlayerCore.checkStatusForSleep()
      case .playing:
        PlayerCore.checkStatusForSleep()
        if player == PlayerCore.lastActive {
          if RemoteCommandController.useSystemMediaControl {
            NowPlayingInfoManager.updateInfo(state: .playing)
          }
          if player.mainWindow.pipStatus == .inPIP {
            player.mainWindow.pip.playing = true
          }
        }
      case .paused:
        PlayerCore.checkStatusForSleep()
        if player == PlayerCore.lastActive {
          if RemoteCommandController.useSystemMediaControl {
            NowPlayingInfoManager.updateInfo(state: .paused)
          }
          if player.mainWindow.pipStatus == .inPIP {
            player.mainWindow.pip.playing = false
          }
        }
      default: return
      }
    }
  }

  var isSeeking: Bool = false

  var currentURL: URL? {
    didSet {
      if let url = currentURL {
        mpvMd5 = Utility.mpvWatchLaterMd5(url.path)
      } else {
        mpvMd5 = nil
      }
    }
  }
  var isNetworkResource: Bool = false
  var mpvMd5: String?

  var videoWidth: Int?
  var videoHeight: Int?

  var displayWidth: Int?
  var displayHeight: Int?

  var rotation: Int = 0

  var videoPosition: VideoTime?
  var videoDuration: VideoTime?

  var cachedWindowScale: Double = 1.0

  func constrainVideoPosition() {
    guard let duration = videoDuration, let position = videoPosition else { return }
    if position.second < 0 { position.second = 0 }
    if position.second > duration.second { position.second = duration.second }
  }

  var isAudio: MediaIsAudioStatus {
    guard !isNetworkResource else { return .notAudio }
    let noVideoTrack = videoTracks.isEmpty
    let noAudioTrack = audioTracks.isEmpty
    if noVideoTrack && noAudioTrack {
      return .unknown
    }
    let allVideoTracksAreAlbumCover = !videoTracks.contains { !$0.isAlbumart }
    return (noVideoTrack || allVideoTracksAreAlbumCover) ? .isAudio : .notAudio
  }

  var justStartedFile: Bool = false
  var justOpenedFile: Bool = false
  var shouldAutoLoadFiles: Bool = false
  var isMatchingSubtitles = false
  var disableOSDForFileLoading: Bool = false

  /** The current applied aspect, used for find current aspect in menu, etc. Maybe not a good approach. */
  var unsureAspect: String = "Default"
  var unsureCrop: String = "None" // TODO: rename this to "selectedCrop"
  var cropFilter: MPVFilter?
  var flipFilter: MPVFilter?
  var mirrorFilter: MPVFilter?
  var audioEqFilter: MPVFilter?
  var delogoFilter: MPVFilter?

  var deinterlace: Bool = false
  var hwdec: String = "no"
  var hwdecEnabled: Bool {
    hwdec != "no"
  }
  var hdrAvailable: Bool = false
  var hdrEnabled: Bool = true

  // video equalizer
  var brightness: Int = 0
  var contrast: Int = 0
  var saturation: Int = 0
  var gamma: Int = 0
  var hue: Int = 0

  var volume: Double = 50

  var isMuted: Bool = false

  var playSpeed: Double = 1

  var audioDelay: Double = 0
  var subDelay: Double = 0

  // cache related
  var pausedForCache: Bool = false
  var cacheUsed: Int = 0
  var cacheSpeed: Int = 0
  var cacheTime: Int = 0
  var bufferingState: Int = 0

  var audioTracks: [MPVTrack] = []
  var videoTracks: [MPVTrack] = []
  @Atomic var subTracks: [MPVTrack] = []

  var abLoopStatus: LoopStatus = .cleared

  /** Selected track IDs. Use these (instead of `isSelected` of a track) to check if selected */
  @Atomic var aid: Int?
  @Atomic var sid: Int?
  @Atomic var vid: Int?
  @Atomic var secondSid: Int?

  var isSubVisible = true
  var isSecondSubVisible = true

  var subEncoding: String?

  func trackList(_ type: MPVTrack.TrackType) -> [MPVTrack] {
    switch type {
    case .video: return videoTracks
    case .audio: return audioTracks
    case .sub, .secondSub: return subTracks
    }
  }

  func trackId(_ type: MPVTrack.TrackType) -> Int? {
    switch type {
    case .video: return vid
    case .audio: return aid
    case .sub: return sid
    case .secondSub: return secondSid
    }
  }

  func currentTrack(_ type: MPVTrack.TrackType) -> MPVTrack? {
    let id: Int?, list: [MPVTrack]
    switch type {
    case .video:
      id = vid
      list = videoTracks
    case .audio:
      id = aid
      list = audioTracks
    case .sub:
      id = sid
      list = subTracks
    case .secondSub:
      id = secondSid
      list = subTracks
    }
    if let id = id {
      return list.first { $0.id == id }
    } else {
      return nil
    }
  }

  /// Copy of the mpv playlist.
  /// - Important: Obtaining video duration, playback progress, and metadata for files in the playlist can be a slow operation, so a
  ///     background task is used and the results are cached. Thus the playlist must be protected with a lock as well as the cache.
  ///     To avoid the need to lock multiple locks the cache properties are always accessed while holding the playlist lock. The cache
  ///     properties are private to force all access to be through class methods that properly coordinate thread access.
  @Atomic var playlist: [MPVPlaylistItem] = []
  private var cachedVideoDurationAndProgress: [String: (duration: Double?, progress: Double?)] = [:]
  private var cachedMetadata: [String: (title: String?, album: String?, artist: String?)] = [:]

  var chapters: [MPVChapter] = []
  var chapter = 0

  @Atomic var matchedSubs: [String: [URL]] = [:]

  func getMatchedSubs(_ file: String) -> [URL]? { $matchedSubs.withLock { $0[file] } }

  var currentSubsInfo: [FileInfo] = []
  var currentVideosInfo: [FileInfo] = []

  func calculateTotalDuration() -> Double? {
    $playlist.withLock { playlist in
      var totalDuration: Double? = 0
      for p in playlist {
        if let duration = cachedVideoDurationAndProgress[p.filename]?.duration {
          totalDuration! += duration > 0 ? duration : 0
        } else {
          // Cache is missing an entry, can't provide a total.
          return nil
        }
      }
      return totalDuration
    }
  }

  func calculateTotalDuration(_ indexes: IndexSet) -> Double {
    $playlist.withLock { playlist in
      indexes
        .compactMap { cachedVideoDurationAndProgress[playlist[$0].filename]?.duration }
        .compactMap { $0 > 0 ? $0 : 0 }
        .reduce(0, +)
    }
  }

  /// Return the cached duration and progress for the given file if present in the cache.
  /// - Parameter file: File to return the duration and progress for.
  /// - Returns: A tuple containing the duration and progress if found in the cache, otherwise `nil`.
  /// - Important: To avoid the need to lock multiple locks the cache properties are always accessed while holding the playlist lock.
  func getCachedVideoDurationAndProgress(_ file: String) -> (duration: Double?, progress: Double?)? {
    $playlist.withLock { _ in
      cachedVideoDurationAndProgress[file]
    }
  }

  /// Store the given duration for the given file in the cache.
  /// - Parameters:
  ///   - file: File to store the duration for.
  ///   - duration: The duration of the file.
  /// - Important: To avoid the need to lock multiple locks the cache properties are always accessed while holding the playlist lock.
  func setCachedVideoDuration(_ file: String, _ duration: Double) {
    $playlist.withLock { _ in
      cachedVideoDurationAndProgress[file]?.duration = duration
    }
  }

  /// Store the given duration and progress for the given file in the cache.
  /// - Parameters:
  ///   - file: File to store the duration and progress for.
  ///   - value: A tuple containing the duration and progress for the file.
  /// - Important: To avoid the need to lock multiple locks the cache properties are always accessed while holding the playlist lock.
  func setCachedVideoDurationAndProgress(_ file: String, _ value: (duration: Double?, progress: Double?)) {
    $playlist.withLock { _ in
      cachedVideoDurationAndProgress[file] = value
    }
  }

  /// Return the cached metadata for the given file if present in the cache.
  /// - Parameter file: File to return the metadata for.
  /// - Returns: A tuple containing the title, album and artist if found in the cache, otherwise `nil`.
  /// - Important: To avoid the need to lock multiple locks the cache properties are always accessed while holding the playlist lock.
  func getCachedMetadata(_ file: String) -> (title: String?, album: String?, artist: String?)? {
    $playlist.withLock { _ in
      cachedMetadata[file]
    }
  }

  /// Store the given metadata for the given file in the cache.
  /// - Parameters:
  ///   - file: File to store the title, album and artist for.
  ///   - value: A tuple containing the duration and progress for the file.
  /// - Important: To avoid the need to lock multiple locks the cache properties are always accessed while holding the playlist lock.
  func setCachedMetadata(_ file: String, _ value: (title: String?, album: String?, artist: String?)) {
    $playlist.withLock { _ in
      cachedMetadata[file] = value
    }
  }

  @Atomic var thumbnailsReady = false
  @Atomic var thumbnailsProgress: Double = 0
  @Atomic var thumbnails: [FFThumbnail] = []

  func getThumbnail(forSecond sec: Double) -> FFThumbnail? {
    $thumbnails.withLock {
      guard !$0.isEmpty else { return nil }
      var tb = $0.last!
      for i in 0..<$0.count {
        if $0[i].realTime >= sec {
          tb = $0[(i == 0 ? i : i - 1)]
          break
        }
      }
      return tb
    }
  }
}
