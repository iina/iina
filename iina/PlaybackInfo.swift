//
//  PlaybackInfo.swift
//  iina
//
//  Created by lhc on 21/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation

class PlaybackInfo {

  var fileLoading: Bool = false

  var currentURL: URL?
  var currentFolder: URL?
  var isNetworkResource: Bool = false

  var videoWidth: Int?
  var videoHeight: Int?

  var displayWidth: Int?
  var displayHeight: Int?

  var rotation: Int = 0

  var videoPosition: VideoTime? {
    didSet {
      guard let duration = videoDuration else { return }
      if videoPosition!.second < 0 { videoPosition!.second = 0 }
      if videoPosition!.second > duration.second { videoPosition!.second = duration.second }
    }
  }

  var videoDuration: VideoTime?

  var isSeeking: Bool = false
  var isPaused: Bool = false

  var justStartedFile: Bool = false
  var justOpenedFile: Bool = false
  var disableOSDForFileLoading: Bool = false

  /** The current applied aspect, used for find current aspect in menu, etc. Maybe not a good approach. */
  var unsureAspect: String = "Default"
  var unsureCrop: String = "None"
  var cropFilter: MPVFilter?
  var flipFilter: MPVFilter?
  var mirrorFilter: MPVFilter?
  var audioEqFilter: MPVFilter?

  var deinterlace: Bool = false

  // video equalizer
  var brightness: Int = 0
  var contrast: Int = 0
  var saturation: Int = 0
  var gamma: Int = 0
  var hue: Int = 0

  var volume: Double = 50

  var isMuted: Bool = false

  var playSpeed: Double = 0

  var audioDelay: Double = 0
  var subDelay: Double = 0

  // cache related
  var pausedForCache: Bool = false
  var cacheSize: Int = 0
  var cacheUsed: Int = 0
  var cacheSpeed: Int = 0
  var cacheTime: Int = 0
  var bufferingState: Int = 0

  var audioTracks: [MPVTrack] = []
  var videoTracks: [MPVTrack] = []
  var subTracks: [MPVTrack] = []

  var abLoopStatus: Int = 0 // 0: none, 1: A set, 2: B set (looping)

  /** Selected track IDs. Use these (instead of `isSelected` of a track) to check if selected */
  var aid: Int?
  var sid: Int?
  var vid: Int?
  var secondSid: Int?

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
      return list.filter { $0.id == id }.at(0)
    } else {
      return nil
    }
  }

  var playlist: [MPVPlaylistItem] = []
  var chapters: [MPVChapter] = []

  var matchedSubs: [String: [URL]] = [:]
  var commonPrefixes: [String: [FileInfo]] = [:]
  var currentVideosInfo: [FileInfo] = []
}
