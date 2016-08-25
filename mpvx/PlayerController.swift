//
//  PlayerController.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlayerController: NSObject {
  
  let ud: UserDefaults = UserDefaults.standard
  
  lazy var mainWindow: MainWindow = {
    let window = MainWindow()
    window.playerController = self
    return window
  }()
  
  lazy var mpvController: MPVController = {
    let controller = MPVController(playerController: self)
    return controller
  }()
  
  lazy var preferenceWindow: PreferenceWindow = {
    let window = PreferenceWindow()
    return window
  }()
  
  lazy var info: PlaybackInfo = PlaybackInfo()
  
  var syncPlayTimeTimer: Timer?
  
  var statusPaused: Bool = false
  
  var aspectRegEx = Utility.Regex("\\A\\d+:\\d+\\Z")
  
  // Open a file
  func openFile(_ url: URL!) {
    let path = url.path
    guard path != nil else {
      Utility.log("Error: empty file path or url")
      return
    }
    Utility.log("Open File \(path!)")
    info.currentURL = url
    mainWindow.showWindow(nil)
    // Send load file command
    info.fileLoading = true
    mpvController.mpvCommand([MPVCommand.loadfile, path, nil])
  }
  
  func startMPV() {
    mpvController.mpvInit()
  }
  
  func startMPVOpenGLCB(_ videoView: VideoView) {
    let mpvGLContext = mpvController.mpvInitCB()
    videoView.mpvGLContext = OpaquePointer(mpvGLContext)
  }
  
  // Terminate mpv
  func terminateMPV() {
    syncPlayTimeTimer?.invalidate()
    mpvController.mpvQuit()
    mainWindow.videoView.clearGLContext()
  }
  
  // MARK: - mpv commands
  
  /** Pause / resume. Reset speed to 0 when pause. */
  func togglePause(_ set: Bool?) {
    if let setPause = set {
      mpvController.mpvSetFlagProperty(MPVProperty.pause, setPause)
      if setPause {
        setSpeed(0)
      }
    } else {
      if (info.isPaused) {
        mpvController.mpvSetFlagProperty(MPVProperty.pause, false)
      } else {
        mpvController.mpvSetFlagProperty(MPVProperty.pause, true)
        setSpeed(0)
      }
    }
  }
  
  func stop() {
    mpvController.mpvCommand([MPVCommand.stop, nil])
  }
  
  func toogleMute(_ set: Bool?) {
    if let setMute = set {
      mpvController.mpvSetFlagProperty(MPVProperty.mute, setMute)
    } else {
      if (mpvController.mpvGetFlagProperty(MPVProperty.mute)) {
        mpvController.mpvSetFlagProperty(MPVProperty.mute, false)
      } else {
        mpvController.mpvSetFlagProperty(MPVProperty.mute, true)
      }
    }
  }
  
  func seek(percent: Double) {
    let seekMode = ud.bool(forKey: Preference.Key.useExactSeek) ? "absolute-percent+exact" : "absolute-percent"
    mpvController.mpvCommand([MPVCommand.seek, "\(percent)", seekMode, nil])
  }

  func seek(relativeSecond: Double) {
    let seekMode = ud.bool(forKey: Preference.Key.useExactSeek) ? "relative+exact" : "relative"
    mpvController.mpvCommand([MPVCommand.seek, "\(relativeSecond)", seekMode, nil])
  }
  
  func seek(absoluteSecond: Double) {
    mpvController.mpvCommand([MPVCommand.seek, "\(absoluteSecond)", "absolute+exact", nil])
  }
  
  func frameStep(backwards: Bool) {
    if backwards {
      mpvController.mpvCommand([MPVCommand.frameBackStep, nil])
    } else {
      mpvController.mpvCommand([MPVCommand.frameStep, nil])
    }
  }
  
  func screenShot() {
    let option = ud.bool(forKey: Preference.Key.screenshotIncludeSubtitle) ? "subtitles" : "video"
    mpvController.mpvCommand([MPVCommand.screenshot, option, nil])
  }
  
  func abLoop() {
    // may subject to change
    mpvController.mpvCommand([MPVCommand.abLoop, nil])
    let a = mpvController.mpvGetDoubleProperty(MPVProperty.abLoopA)
    let b = mpvController.mpvGetDoubleProperty(MPVProperty.abLoopB)
    if a == 0 && b == 0 {
      info.abLoopStatus = 0
    } else if b != 0 {
      info.abLoopStatus = 2
    } else {
      info.abLoopStatus = 1
    }
  }
  
  func setVolume(_ volume: Int) {
    info.volume = volume
    mpvController.mpvSetIntProperty(MPVProperty.volume, volume)
  }
  
  func setTrack(_ index: Int, forType: MPVTrack.TrackType) {
    let name: String
    switch forType {
    case .audio:
      name = MPVProperty.aid
    case .video:
      name = MPVProperty.vid
    case .sub:
      name = MPVProperty.sid
    case .secondSub:
      name = MPVProperty.secondarySid
    }
    mpvController.mpvSetIntProperty(name, index)
    getSelectedTracks()
  }

  /** Set speed. A negative speed -x means slow by x times */
  func setSpeed(_ speed: Double) {
    var realSpeed = speed
    if realSpeed == 0 {
      realSpeed = 1
    } else if realSpeed < 0 {
      realSpeed = -1 / realSpeed
    }
    mpvController.mpvSetDoubleProperty(MPVProperty.speed, realSpeed)
    info.playSpeed = speed
  }
  
  func setVideoAspect(_ aspect: String) {
    if aspectRegEx.matches(aspect) {
      mpvController.mpvSetStringProperty(MPVProperty.videoAspect, aspect)
    } else {
      mpvController.mpvSetStringProperty(MPVProperty.videoAspect, "-1")
    }
  }
  
  func setVideoRotate(_ degree: Int) {
    if [0, 90, 270, 360].index(of: degree) >= 0 {
      mpvController.mpvSetIntProperty(MPVProperty.videoRotate, degree)
      info.rotation = degree
    }
  }
  
  func loadExternalAudioFile(_ url: URL) {
    if let path  = url.path {
      mpvController.mpvCommand([MPVCommand.audioAdd, path, nil])
      getTrackInfo()
      getSelectedTracks()
    }
  }
  
  func loadExternalSubFile(_ url: URL) {
    if let path  = url.path {
      mpvController.mpvCommand([MPVCommand.subAdd, path, nil])
      getTrackInfo()
      getSelectedTracks()
    }
  }
  
  func setAudioDelay(_ delay: Double) {
    mpvController.mpvSetDoubleProperty(MPVProperty.audioDelay, delay)
  }
  
  func setSubDelay(_ delay: Double) {
    mpvController.mpvSetDoubleProperty(MPVProperty.subDelay, delay)
  }
  
  func addToPlaylist(_ path: String) {
    mpvController.mpvCommand([MPVCommand.loadfile, path, "append", nil])
    getPLaylist()
  }
  
  func playFile(_ path: String) {
    mpvController.mpvCommand([MPVCommand.loadfile, path, "replace", nil])
    getPLaylist()
  }
  
  func playFileInPlaylist(_ pos: Int) {
    mpvController.mpvSetIntProperty(MPVProperty.playlistPos, pos)
    getPLaylist()
  }
  
  /** This function is called right after file loaded. Should load all meta info here. */
  func fileLoaded() {
    guard let vwidth = info.videoWidth, vheight = info.videoHeight else {
      Utility.fatal("Cannot get video width and height")
      return
    }
    info.fileLoading = false
    DispatchQueue.main.sync {
      self.getTrackInfo()
      self.getSelectedTracks()
      self.getPLaylist()
      syncPlayTimeTimer = Timer.scheduledTimer(timeInterval: TimeInterval(AppData.getTimeInterval),
                                               target: self, selector: #selector(self.syncUITime), userInfo: nil, repeats: true)
      mainWindow.updateTitle()
      mainWindow.adjustFrameByVideoSize(vwidth, vheight)
    }
  }
  
  func notifyMainWindowVideoSizeChanged() {
    guard let dwidth = info.displayWidth, dheight = info.displayHeight else {
      Utility.fatal("Cannot get video width and height")
      return
    }
    if dwidth != 0 && dheight != 0 {
      DispatchQueue.main.sync {
        mainWindow.adjustFrameByVideoSize(dwidth, dheight)
      }
    }
  }
  
  /** Sync with UI in MainWindow */
  
  enum SyncUIOption {
    case Time
    case PlayButton
    case MuteButton
  }
  
  func syncUITime() {
    syncUI(.Time)
  }
  
  func syncUI(_ option: SyncUIOption) {
    switch option {
    case .Time:
      let time = mpvController.mpvGetIntProperty(MPVProperty.timePos)
      info.videoPosition!.second = time
      DispatchQueue.main.async {
        self.mainWindow.updatePlayTime(withDuration: false, andProgressBar: true)
      }
    case .PlayButton:
      let pause = mpvController.mpvGetFlagProperty(MPVProperty.pause)
      info.isPaused = pause
      DispatchQueue.main.async {
        self.mainWindow.updatePlayButtonState(pause ? NSOffState : NSOnState)
      }
    case .MuteButton:
      let mute = mpvController.mpvGetFlagProperty(MPVProperty.mute)
      DispatchQueue.main.async {
        self.mainWindow.muteButton.state = mute ? NSOnState : NSOffState
      }
    }
  }
  
  /** Get info from mpv */
  
  private func getTrackInfo() {
    info.audioTracks.removeAll(keepingCapacity: true)
    info.videoTracks.removeAll(keepingCapacity: true)
    info.subTracks.removeAll(keepingCapacity: true)
    let trackCount = mpvController.mpvGetIntProperty(MPVProperty.trackListCount)
    for index in 0...trackCount-1 {
      // get info for each track
      let track = MPVTrack(id:         mpvController.mpvGetIntProperty(MPVProperty.trackListNId(index)),
                           type: MPVTrack.TrackType(rawValue:
                                       mpvController.mpvGetStringProperty(MPVProperty.trackListNType(index))!
                           )!,
                           isDefault:  mpvController.mpvGetFlagProperty(MPVProperty.trackListNDefault(index)),
                           isForced:   mpvController.mpvGetFlagProperty(MPVProperty.trackListNForced(index)),
                           isSelected: mpvController.mpvGetFlagProperty(MPVProperty.trackListNSelected(index)),
                           isExternal: mpvController.mpvGetFlagProperty(MPVProperty.trackListNExternal(index)))
      track.srcId = mpvController.mpvGetIntProperty(MPVProperty.trackListNSrcId(index))
      track.title = mpvController.mpvGetStringProperty(MPVProperty.trackListNTitle(index))
      track.lang = mpvController.mpvGetStringProperty(MPVProperty.trackListNLang(index))
      track.codec = mpvController.mpvGetStringProperty(MPVProperty.trackListNCodec(index))
      track.externalFilename = mpvController.mpvGetStringProperty(MPVProperty.trackListNExternalFilename(index))
      // add to lists
      switch track.type {
      case .audio:
        info.audioTracks.append(track)
      case .video:
        info.videoTracks.append(track)
      case .sub:
        info.subTracks.append(track)
      default:
        break
      }
    }
  }
  
  private func getSelectedTracks() {
    info.aid = mpvController.mpvGetIntProperty(MPVProperty.aid)
    info.vid = mpvController.mpvGetIntProperty(MPVProperty.vid)
    info.sid = mpvController.mpvGetIntProperty(MPVProperty.sid)
    info.secondSid = mpvController.mpvGetIntProperty(MPVProperty.secondarySid)
  }
  
  private func getPLaylist() {
    info.playlist.removeAll()
    let playlistCount = mpvController.mpvGetIntProperty(MPVProperty.playlistCount)
    for index in 0...playlistCount-1 {
      let playlistItem = MPVPlaylistItem(filename: mpvController.mpvGetStringProperty(MPVProperty.playlistNFilename(index))!,
                                         isCurrent: mpvController.mpvGetFlagProperty(MPVProperty.playlistNCurrent(index)),
                                         isPlaying: mpvController.mpvGetFlagProperty(MPVProperty.playlistNPlaying(index)),
                                         title: mpvController.mpvGetStringProperty(MPVProperty.playlistNTitle(index)))
      info.playlist.append(playlistItem)
    }
  }

}
