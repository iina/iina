//
//  PlaybackInfo.swift
//  iina
//
//  Created by lhc on 21/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class PlaybackInfo {

  unowned let player: PlayerCore

  init(_ pc: PlayerCore) {
    player = pc
  }

  var isIdle: Bool = true {
    didSet {
      PlayerCore.checkStatusForSleep()
    }
  }
  var fileLoading: Bool = false

  var currentURL: URL? {
    didSet {
      if let url = currentURL {
        mpvMd5 = Utility.mpvWatchLaterMd5(url.path)
      } else {
        mpvMd5 = nil
      }
    }
  }
  var currentFolder: URL?
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
    guard let duration = videoDuration else { return }
    if videoPosition!.second < 0 { videoPosition!.second = 0 }
    if videoPosition!.second > duration.second { videoPosition!.second = duration.second }
  }

  var isSeeking: Bool = false

  var isPaused: Bool = false {
    didSet {
      PlayerCore.checkStatusForSleep()
      if player == PlayerCore.lastActive {
        if #available(macOS 10.13, *), RemoteCommandController.useSystemMediaControl {
          NowPlayingInfoManager.updateState(isPaused ? .paused : .playing)
        }
        if #available(macOS 10.12, *), player.mainWindow.pipStatus == .inPIP {
          player.mainWindow.pip.playing = isPlaying
        }
      }
    }
  }
  var isPlaying: Bool {
    get {
      return !isPaused
    }
    set {
      isPaused = !newValue
    }
  }

  var justLaunched: Bool = true
  var justStartedFile: Bool = false
  var justOpenedFile: Bool = false
  var shouldAutoLoadFiles: Bool = false
  var isMatchingSubtitles = false
  var disableOSDForFileLoading: Bool = false

  /** The current applied aspect, used for find current aspect in menu, etc. Maybe not a good approach. */
  var unsureAspect: String = "Default"
  var unsureCrop: String = "None"
  var cropFilter: MPVFilter?
  var flipFilter: MPVFilter?
  var mirrorFilter: MPVFilter?
  var audioEqFilters: [MPVFilter?]?
  var delogoFilter: MPVFilter?

  var deinterlace: Bool = false
  var hwdec: String = "no"
  var hwdecEnabled: Bool {
    hwdec != "no"
  }

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
  var subTracks: [MPVTrack] = []

  var abLoopStatus: Int = 0 // 0: none, 1: A set, 2: B set (looping)
  
  //  FIXME: Make track indices concrete, non-optional.
  /** Selected track IDs. Use these (instead of `isSelected` of a track) to check if selected */
  var aid: Int?
  var vid: Int?
  //  FIXME: Use a tupple for the 2 subtitle track indices.
  /// The first subtitle track index.
  var sid: Int? = 0 {
    didSet(previousFirstSubtitleTrackIndex) {
      //  In order to prevent a didSet loop between the first subtitle track index's and the subtitles state's observers, we need to ensure that the subtitle track index did change before everything.
      guard sid != previousFirstSubtitleTrackIndex else { return }
      recoveredFirstSubtitleTrackIndex = previousFirstSubtitleTrackIndex
      guard let firstSubtitleTrackIndex = sid, let secondSubtitleTrackIndex = secondSid else { return }
      subtitlesAreEnabled = firstSubtitleTrackIndex > 0 || secondSubtitleTrackIndex > 0
    }
  }
  
  /// The second subtitle track index.
  var secondSid: Int? = 0 {
    didSet(previousSecondSubtitleTrackIndex) {
      //  In order to prevent a didSet loop between the second subtitle track index's and the subtitles state's observers, we need to ensure that the subtitle track index did change before everything.
      guard secondSid != previousSecondSubtitleTrackIndex else { return }
      recoveredSecondSubtitleTrackIndex = previousSecondSubtitleTrackIndex
      guard let firstSubtitleTrackIndex = sid, let secondSubtitleTrackIndex = secondSid else { return }
      subtitlesAreEnabled = firstSubtitleTrackIndex > 0 || secondSubtitleTrackIndex > 0
    }
  }
  
  /// The first subtitle track index to revert to when subtitles are (re-)enabled.
  ///
  /// The default value is `1`. A video starts with no subtitles, with subtitles in the off state (disabled). When the user enables subtitles for the first time, the first subtitle switches to the 1st track.
  var recoveredFirstSubtitleTrackIndex: Int? = 1
  
  /// The second subtitle track index to revert to when subtitles are (re-)enabled.
  ///
  /// The default value is `0`. A video starts with no subtitles, with subtitles in the off state (disabled). When the user enables subtitles for the first time, the second subtitle stays off.
  var recoveredSecondSubtitleTrackIndex: Int? = 0
  
  //  FIXME: Remove `subtitlesAreDisabled`.
  var subtitlesAreDisabled: Bool {
    get { !subtitlesAreEnabled }
    set(newSubtitleState) { subtitlesAreEnabled = !newSubtitleState }
  }
  
  /// The Boolean value indicating whether the subtitles are on (enabled).
  var subtitlesAreEnabled: Bool = false {
    //  FIXME: Fix the property observer logic.
    //  Everything before `sendOSD` should be in a `willSet` observer, but it will lead to `sendOSD` being called twise, so everything is in `didSet` for now.
    didSet(previousSubtitlesState) {
      //  In order to prevent a didSet loop between the subtitle tracks indices's and the subtitles state's observers, we need to ensure that the subtitles state did change before everything.
      guard previousSubtitlesState != subtitlesAreEnabled else { return }
      player.mpv.setInt(MPVOption.TrackSelection.sid, subtitlesAreEnabled ? recoveredFirstSubtitleTrackIndex! : 0)
      player.mpv.setInt(MPVOption.Subtitles.secondarySid, subtitlesAreEnabled ? recoveredSecondSubtitleTrackIndex! : 0)
      //  FIXME: sendOSD doesn't work here because as soon as a sub track changes, the property listeners in MPVController will fire their own OSD message effectively making the ones here unseen
      player.sendOSD(subtitlesAreEnabled ? .enableSubtitles : .disableSubtitles)
    }
  }

  var subEncoding: String?

  var haveDownloadedSub: Bool = false

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

  var playlist: [MPVPlaylistItem] = []
  var chapters: [MPVChapter] = []
  var chapter = 0

  var matchedSubs: [String: [URL]] = [:]
  var currentSubsInfo: [FileInfo] = []
  var currentVideosInfo: [FileInfo] = []
  var cachedVideoDurationAndProgress: [String: (duration: Double?, progress: Double?)] = [:]

  var thumbnailsReady = false
  var thumbnailsProgress: Double = 0
  var thumbnails: [FFThumbnail] = []

  func getThumbnail(forSecond sec: Double) -> FFThumbnail? {
    guard !thumbnails.isEmpty else { return nil }
    var tb = thumbnails.last!
    for i in 0..<thumbnails.count {
      if thumbnails[i].realTime >= sec {
        tb = thumbnails[(i == 0 ? i : i - 1)]
        break
      }
    }
    return tb
  }
}
