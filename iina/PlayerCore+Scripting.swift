//
//  PlayerCore+Scripting.swift
//  iina
//
//  Created by Nate Weaver on 2020-03-04.
//  Copyright © 2020 lhc. All rights reserved.
//

import AppKit

@objc extension PlayerCore {

  override var classCode: FourCharCode {
    return "cPla"
  }

  override var objectSpecifier: NSScriptObjectSpecifier? {
    let containerClass = NSScriptClassDescription(for: type(of: NSApp));

    return NSUniqueIDSpecifier(containerClassDescription: containerClass!, containerSpecifier: nil, key: "orderedPlayers", uniqueID: self.label as Any)
  }

}

// MARK: Scripting Properties

private extension FourCharCode {
  static let playing = FourCharCode("kPSP")
  static let paused = FourCharCode("kPSp")
  static let seeking = FourCharCode("kPSS")
}

@objc extension PlayerCore {

  var uniqueID: String {
    return label
  }

  var scriptingName: String? {
    return info.currentURL?.lastPathComponent
  }

  var scriptingState: FourCharCode {
    return info.isPaused ?
      (info.isSeeking ? .seeking : .paused) :
      .playing
  }

  var scriptingPlaySpeed: Double {
    get {
      return info.playSpeed
    }
    set {
      setSpeed(newValue)
    }
  }

  var scriptingFileLoop: Bool {
    get {
      return mpv.getFlag(MPVOption.PlaybackControl.loopFile)
    }
    set {
      mpv.setFlag(MPVOption.PlaybackControl.loopFile, newValue)
    }
  }

  var scriptingVolume: Double {
    get {
      return info.volume
    }
    set {
      setVolume(newValue)
    }
  }

  var scriptingIsMuted: Bool {
    get {
      return info.isMuted
    }
    set {
      toggleMute(newValue)
    }
  }

  var scriptingPosition: Double {
    get {
      return info.videoPosition?.second ?? 0
    }
    set {
      seek(absoluteSecond: newValue)
    }
  }

  var scriptingFile: URL? {
    get {
      if let file = info.currentURL {
        return file.isFileURL ? file : nil
      }
      return nil
    }
  }

  var scriptingUrlString: String? {
    get {
      return info.currentURL?.absoluteString
    }
  }

  var scriptingIsInMiniPlayer: Bool {
    get {
      return isInMiniPlayer
    }
    set {
      guard newValue != isInMiniPlayer else { return }
      newValue ? switchToMiniPlayer() : switchBackFromMiniPlayer(automatically: false, showMainWindow: true)
    }
  }

  var scriptingIsFullscreen: Bool {
    get { mainWindow.fsState.isFullscreen }
    set {
      guard newValue != mainWindow.fsState.isFullscreen else { return }
      scriptingIsInMiniPlayer = false
      mainWindow.toggleWindowFullScreen()
    }
  }

  var scriptingIsPIP: Bool {
    get { mainWindow.pipStatus == .inPIP }
    set {
      if #available(macOS 10.12, *) {
        if newValue && mainWindow.pipStatus != .inPIP {
          scriptingIsInMiniPlayer = false
          mainWindow.enterPIP()
        } else if !newValue && mainWindow.pipStatus == .inPIP {
          mainWindow.exitPIP()
        }
      }
    }
  }

  var scriptingWindow: NSWindow? {
    return isInMiniPlayer ?
      (miniPlayer.isWindowLoaded ? miniPlayer.window : nil) :
      (mainWindow.isWindowLoaded ? mainWindow.window : nil)
  }

  var scriptingTracks: [MPVTrack] { info.videoTracks + info.audioTracks + info.subTracks }

  var scriptingVideoTracks: [MPVTrack] { info.videoTracks }
  var scriptingAudioTracks: [MPVTrack] { info.audioTracks }
  var scriptingSubtitleTracks: [MPVTrack] { info.subTracks }

  @nonobjc func setCurentTrack(_ track: MPVTrack?, for type: MPVTrack.TrackType) {
    guard let track = track else { return }

    guard track.player === self else {
      NSScriptCommand.current()?.scriptErrorNumber = 1000
      NSScriptCommand.current()?.scriptErrorString = "Track doesn’t belong to player."
      return
    }

    guard track.type == (type == .secondSub ? .sub : type) else {
      NSScriptCommand.current()?.scriptErrorNumber = 1001
      NSScriptCommand.current()?.scriptErrorString = "Track should be of type “\(type.rawValue)” but is of type “\(track.type.rawValue)”."

      return
    }

    setTrack(track.id, forType: type)
  }

  var scriptingCurrentVideoTrack: MPVTrack? {
    get { info.currentTrack(.video) }
    set {
      setCurentTrack(newValue, for: .video)
    }
  }

  var scriptingCurrentAudioTrack: MPVTrack? {
    get { info.currentTrack(.audio) }
    set {
      setCurentTrack(newValue, for: .audio)
    }
  }

  var scriptingCurrentSubtitleTrack: MPVTrack? {
    get { info.currentTrack(.sub) }
    set {
      setCurentTrack(newValue, for: .sub)
    }
  }

  var scriptingSecondSubtitleTrack: MPVTrack? {
    get { info.currentTrack(.secondSub) }
    set {
      setCurentTrack(newValue, for: .secondSub)
    }
  }

  var scriptingAspectRatio: String {
    get { info.unsureAspect }
    set { setVideoAspect(newValue) }
  }

  var scriptingPlaylistItems: [MPVPlaylistItem] { info.playlist }

  var scriptingCurrentPlaylistItem: MPVPlaylistItem? {
    get { info.playlist.first { $0.isCurrent } }
    set {
      guard newValue?.player === self else { return }
      guard let index = newValue?.scriptingIndex else { return }
      playFileInPlaylist(index)
    }
  }

}

// MARK: Command Handlers

@objc extension PlayerCore {

  func handlePlayCommand(_ command: NSScriptCommand) {
    resume()
  }

  func handlePauseCommand(_ command: NSScriptCommand) {
    pause()
  }

  func handlePlayPauseCommand(_ command: NSScriptCommand) {
    info.isPaused ? resume() : pause()
  }

  func handleNextCommand(_ command: NSScriptCommand) {
    navigateInPlaylist(nextMedia: true)
  }

  func handlePreviousCommand(_ command: NSScriptCommand) {
    navigateInPlaylist(nextMedia: false)
  }

}
