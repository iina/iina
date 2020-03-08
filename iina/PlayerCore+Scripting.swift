//
//  PlayerCore+Scripting.swift
//  iina
//
//  Created by Nate Weaver on 2020-03-04.
//  Copyright © 2020 lhc. All rights reserved.
//

import AppKit

extension PlayerCore {

  @objc override var classCode: FourCharCode {
    return NSHFSTypeCodeFromFileType("'cPla'")
  }

  override var objectSpecifier: NSScriptObjectSpecifier? {
    let containerClass = NSScriptClassDescription(for: type(of: NSApp));

    return NSUniqueIDSpecifier(containerClassDescription: containerClass!, containerSpecifier: nil, key: "orderedPlayers", uniqueID: self.label as Any)
  }

}

// MARK: Scripting Properties

extension PlayerCore {

  @objc var uniqueID: String {
    return label
  }

  @objc var scriptingName: String? {
    return info.currentURL?.lastPathComponent
  }

  @objc var scriptingState: FourCharCode {
    return info.isPaused ?
      (info.isSeeking ? NSHFSTypeCodeFromFileType("'kPSS'") : NSHFSTypeCodeFromFileType("'kPSp'")) :
      NSHFSTypeCodeFromFileType("'kPSP'")
  }

  @objc var scriptingPlaySpeed: Double {
    get {
      return info.playSpeed
    }
    set {
      setSpeed(newValue)
    }
  }

  @objc var scriptingFileLoop: Bool {
    get {
      return mpv.getFlag(MPVOption.PlaybackControl.loopFile)
    }
    set {
      mpv.setFlag(MPVOption.PlaybackControl.loopFile, newValue)
    }
  }

  @objc var scriptingVolume: Double {
    get {
      return info.volume
    }
    set {
      setVolume(newValue)
    }
  }

  @objc var scriptingIsMuted: Bool {
    get {
      return info.isMuted
    }
    set {
      toggleMute(newValue)
    }
  }

  @objc var scriptingPosition: Double {
    get {
      return info.videoPosition?.second ?? 0
    }
    set {
      seek(absoluteSecond: newValue)
    }
  }

  @objc var scriptingFile: URL? {
    get {
      if let file = info.currentURL {
        return file.isFileURL ? file : nil
      }
      return nil
    }
  }

  @objc var scriptingUrlString: String? {
    get {
      return info.currentURL?.absoluteString
    }
  }

  @objc var scriptingIsInMiniPlayer: Bool {
    get {
      return isInMiniPlayer
    }
    set {
      guard newValue != isInMiniPlayer else { return }
      newValue ? switchToMiniPlayer() : switchBackFromMiniPlayer(automatically: false, showMainWindow: true)
    }
  }

  @objc var scriptingIsFullscreen: Bool {
    get { mainWindow.fsState.isFullscreen }
    set {
      guard newValue != mainWindow.fsState.isFullscreen else { return }
      scriptingIsInMiniPlayer = false
      mainWindow.toggleWindowFullScreen()
    }
  }

  @objc var scriptingIsPIP: Bool {
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

  @objc var scriptingWindow: NSWindow? {
    return isInMiniPlayer ?
      (miniPlayer.isWindowLoaded ? miniPlayer.window : nil) :
      (mainWindow.isWindowLoaded ? mainWindow.window : nil)
  }

  @objc var scriptingTracks: [MPVTrack] { info.videoTracks + info.audioTracks + info.subTracks }

  @objc var scriptingVideoTracks: [MPVTrack] { info.videoTracks }
  @objc var scriptingAudioTracks: [MPVTrack] { info.audioTracks }
  @objc var scriptingSubtitleTracks: [MPVTrack] { info.subTracks }

  @objc var scriptingCurrentVideoTrack: MPVTrack? {
    get { info.currentTrack(.video) }
    set {
      guard let track = newValue else { return }
      setTrack(track.id, forType: .video)
    }
  }

  @objc var scriptingCurrentAudioTrack: MPVTrack? {
    get { info.currentTrack(.audio) }
    set {
      guard let track = newValue else { return }
      setTrack(track.id, forType: .audio)
    }
  }

  @objc var scriptingCurrentSubtitleTrack: MPVTrack? {
    get { info.currentTrack(.sub) }
    set {
      guard let track = newValue else { return }
      setTrack(track.id, forType: .sub)
    }
  }

  @objc var scriptingSecondSubtitleTrack: MPVTrack? {
    get { info.currentTrack(.secondSub) }
    set {
      guard let track = newValue else { return }
      setTrack(track.id, forType: .secondSub)
    }
  }

  @objc var scriptingAspectRatio: String {
    get { info.unsureAspect }
    set { setVideoAspect(newValue) }
  }

  @objc var scriptingPlaylistItems: [MPVPlaylistItem] { info.playlist }

  @objc var scriptingCurrentPlaylistItem: MPVPlaylistItem? {
    get { info.playlist.first { $0.isCurrent } }
    set {
      guard newValue?.player === self else { return }
      guard let index = newValue?.scriptingIndex else { return }
      playFileInPlaylist(index)
    }
  }

}

// MARK: Command Handlers

extension PlayerCore {

  @objc func handlePlayCommand(_ command: NSScriptCommand) {
    resume()
  }

  @objc func handlePauseCommand(_ command: NSScriptCommand) {
    pause()
  }

  @objc func handlePlayPauseCommand(_ command: NSScriptCommand) {
    info.isPaused ? resume() : pause()
  }

}
