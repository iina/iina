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
    mpvController.command([MPVCommand.loadfile, path, nil])
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
      mpvController.setFlag(MPVProperty.pause, setPause)
      if setPause {
        setSpeed(0)
      }
    } else {
      if (info.isPaused) {
        mpvController.setFlag(MPVProperty.pause, false)
      } else {
        mpvController.setFlag(MPVProperty.pause, true)
        setSpeed(0)
      }
    }
  }
  
  func stop() {
    mpvController.command([MPVCommand.stop, nil])
  }
  
  func toogleMute(_ set: Bool?) {
    if let setMute = set {
      mpvController.setFlag(MPVProperty.mute, setMute)
    } else {
      if (mpvController.getFlag(MPVProperty.mute)) {
        mpvController.setFlag(MPVProperty.mute, false)
      } else {
        mpvController.setFlag(MPVProperty.mute, true)
      }
    }
  }
  
  func seek(percent: Double) {
    let seekMode = ud.bool(forKey: Preference.Key.useExactSeek) ? "absolute-percent+exact" : "absolute-percent"
    mpvController.command([MPVCommand.seek, "\(percent)", seekMode, nil])
  }

  func seek(relativeSecond: Double) {
    let seekMode = ud.bool(forKey: Preference.Key.useExactSeek) ? "relative+exact" : "relative"
    mpvController.command([MPVCommand.seek, "\(relativeSecond)", seekMode, nil])
  }
  
  func seek(absoluteSecond: Double) {
    mpvController.command([MPVCommand.seek, "\(absoluteSecond)", "absolute+exact", nil])
  }
  
  func frameStep(backwards: Bool) {
    if backwards {
      mpvController.command([MPVCommand.frameBackStep, nil])
    } else {
      mpvController.command([MPVCommand.frameStep, nil])
    }
  }
  
  func screenShot() {
    let option = ud.bool(forKey: Preference.Key.screenshotIncludeSubtitle) ? "subtitles" : "video"
    mpvController.command([MPVCommand.screenshot, option, nil])
  }
  
  func abLoop() {
    // may subject to change
    mpvController.command([MPVCommand.abLoop, nil])
    let a = mpvController.getDouble(MPVProperty.abLoopA)
    let b = mpvController.getDouble(MPVProperty.abLoopB)
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
    mpvController.setInt(MPVProperty.volume, volume)
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
    mpvController.setInt(name, index)
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
    mpvController.setDouble(MPVProperty.speed, realSpeed)
    info.playSpeed = speed
  }
  
  func setVideoAspect(_ aspect: String) {
    if aspectRegEx.matches(aspect) {
      mpvController.setString(MPVProperty.videoAspect, aspect)
    } else {
      mpvController.setString(MPVProperty.videoAspect, "-1")
    }
  }
  
  func setVideoRotate(_ degree: Int) {
    if [0, 90, 270, 360].index(of: degree) >= 0 {
      mpvController.setInt(MPVProperty.videoRotate, degree)
      info.rotation = degree
    }
  }
  
  func loadExternalAudioFile(_ url: URL) {
    if let path  = url.path {
      mpvController.command([MPVCommand.audioAdd, path, nil])
      getTrackInfo()
      getSelectedTracks()
    }
  }
  
  func loadExternalSubFile(_ url: URL) {
    if let path  = url.path {
      mpvController.command([MPVCommand.subAdd, path, nil])
      getTrackInfo()
      getSelectedTracks()
    }
  }
  
  func setAudioDelay(_ delay: Double) {
    mpvController.setDouble(MPVProperty.audioDelay, delay)
  }
  
  func setSubDelay(_ delay: Double) {
    mpvController.setDouble(MPVProperty.subDelay, delay)
  }
  
  func addToPlaylist(_ path: String) {
    mpvController.command([MPVCommand.loadfile, path, "append", nil])
    getPLaylist()
  }
  
  func playFile(_ path: String) {
    mpvController.command([MPVCommand.loadfile, path, "replace", nil])
    getPLaylist()
  }
  
  func playFileInPlaylist(_ pos: Int) {
    mpvController.setInt(MPVProperty.playlistPos, pos)
    getPLaylist()
  }
  
  func playChapter(_ pos: Int) {
    let chapter = info.chapters[pos]
    mpvController.command([MPVCommand.seek, "\(chapter.time.second)", "absolute", nil])
    // need to update time pos
    syncUITime()
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
      self.getChapters()
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
    case chapterList
  }
  
  func syncUITime() {
    syncUI(.Time)
  }
  
  func syncUI(_ option: SyncUIOption) {
    switch option {
    case .Time:
      let time = mpvController.getInt(MPVProperty.timePos)
      info.videoPosition!.second = time
      DispatchQueue.main.async {
        self.mainWindow.updatePlayTime(withDuration: false, andProgressBar: true)
      }
    case .PlayButton:
      let pause = mpvController.getFlag(MPVProperty.pause)
      info.isPaused = pause
      DispatchQueue.main.async {
        self.mainWindow.updatePlayButtonState(pause ? NSOffState : NSOnState)
      }
    case .MuteButton:
      let mute = mpvController.getFlag(MPVProperty.mute)
      DispatchQueue.main.async {
        self.mainWindow.muteButton.state = mute ? NSOnState : NSOffState
      }
    case .chapterList:
      DispatchQueue.main.async {
        // this should avoid sending reload when table view is not ready
        if self.mainWindow.isSideBarShowing {
          self.mainWindow.playlistView.chapterTableView.reloadData()
        }
      }
    }
  }
  
  /** Get info from mpv */
  
  private func getTrackInfo() {
    info.audioTracks.removeAll(keepingCapacity: true)
    info.videoTracks.removeAll(keepingCapacity: true)
    info.subTracks.removeAll(keepingCapacity: true)
    let trackCount = mpvController.getInt(MPVProperty.trackListCount)
    for index in 0...trackCount-1 {
      // get info for each track
      let track = MPVTrack(id:         mpvController.getInt(MPVProperty.trackListNId(index)),
                           type:       MPVTrack.TrackType(rawValue: mpvController.getString(MPVProperty.trackListNType(index))!)!,
                           isDefault:  mpvController.getFlag(MPVProperty.trackListNDefault(index)),
                           isForced:   mpvController.getFlag(MPVProperty.trackListNForced(index)),
                           isSelected: mpvController.getFlag(MPVProperty.trackListNSelected(index)),
                           isExternal: mpvController.getFlag(MPVProperty.trackListNExternal(index)))
      track.srcId = mpvController.getInt(MPVProperty.trackListNSrcId(index))
      track.title = mpvController.getString(MPVProperty.trackListNTitle(index))
      track.lang = mpvController.getString(MPVProperty.trackListNLang(index))
      track.codec = mpvController.getString(MPVProperty.trackListNCodec(index))
      track.externalFilename = mpvController.getString(MPVProperty.trackListNExternalFilename(index))
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
    info.aid = mpvController.getInt(MPVProperty.aid)
    info.vid = mpvController.getInt(MPVProperty.vid)
    info.sid = mpvController.getInt(MPVProperty.sid)
    info.secondSid = mpvController.getInt(MPVProperty.secondarySid)
  }
  
  private func getPLaylist() {
    info.playlist.removeAll()
    let playlistCount = mpvController.getInt(MPVProperty.playlistCount)
    for index in 0...playlistCount-1 {
      let playlistItem = MPVPlaylistItem(filename:  mpvController.getString(MPVProperty.playlistNFilename(index))!,
                                         isCurrent: mpvController.getFlag(MPVProperty.playlistNCurrent(index)),
                                         isPlaying: mpvController.getFlag(MPVProperty.playlistNPlaying(index)),
                                         title:     mpvController.getString(MPVProperty.playlistNTitle(index)))
      info.playlist.append(playlistItem)
    }
  }
  
  private func getChapters() {
    info.chapters.removeAll()
    let chapterCount = mpvController.getInt(MPVProperty.chapterListCount)
    if chapterCount == 0 {
      return
    }
    for index in 0...chapterCount-1 {
      let chapter = MPVChapter(title:     mpvController.getString(MPVProperty.chapterListNTitle(index)),
                               startTime: mpvController.getInt(MPVProperty.chapterListNTime(index)),
                               index:     index)
      info.chapters.append(chapter)
    }
  }

}
