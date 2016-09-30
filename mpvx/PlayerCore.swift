//
//  PlayerCore.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlayerCore: NSObject {
  
  static let shared = PlayerCore()
  
  let ud: UserDefaults = UserDefaults.standard
  
  lazy var mainWindow: MainWindowController = MainWindowController()
  lazy var mpvController: MPVController = MPVController()
  lazy var preferenceWindow: PreferenceWindow = PreferenceWindow()
  lazy var info: PlaybackInfo = PlaybackInfo()
  
  var syncPlayTimeTimer: Timer?
  
  var statusPaused: Bool = false
  
  // MARK: - Control commands
  
  // Open a file
  func openFile(_ url: URL?) {
    let path = url?.path
    guard path != nil else {
      Utility.log("Error: empty file path or url")
      return
    }
    Utility.log("Open File \(path!)")
    info.currentURL = url!
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
  
  // MARK: - MPV commands
  
  /** Pause / resume. Reset speed to 0 when pause. */
  func togglePause(_ set: Bool?) {
    if let setPause = set {
      mpvController.setFlag(MPVOption.PlaybackControl.pause, setPause)
      if setPause {
        setSpeed(0)
      }
    } else {
      if (info.isPaused) {
        mpvController.setFlag(MPVOption.PlaybackControl.pause, false)
      } else {
        mpvController.setFlag(MPVOption.PlaybackControl.pause, true)
        setSpeed(0)
      }
    }
  }
  
  func stop() {
    mpvController.command([MPVCommand.stop, nil])
  }
  
  func toogleMute(_ set: Bool?) {
    let newState = set ?? !mpvController.getFlag(MPVOption.Audio.mute)
    mpvController.setFlag(MPVOption.Audio.mute, newState)
    info.isMuted = newState
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
    let a = mpvController.getDouble(MPVOption.PlaybackControl.abLoopA)
    let b = mpvController.getDouble(MPVOption.PlaybackControl.abLoopB)
    if a == 0 && b == 0 {
      info.abLoopStatus = 0
    } else if b != 0 {
      info.abLoopStatus = 2
    } else {
      info.abLoopStatus = 1
    }
  }
  
  func setVolume(_ volume: Int) {
    let realVolume = volume.constrain(min: 0, max: 100)
    info.volume = realVolume
    mpvController.setInt(MPVOption.Audio.volume, realVolume)
    ud.set(realVolume, forKey: Preference.Key.softVolume)
  }
  
  func setTrack(_ index: Int, forType: MPVTrack.TrackType) {
    let name: String
    switch forType {
    case .audio:
      name = MPVOption.TrackSelection.aid
    case .video:
      name = MPVOption.TrackSelection.vid
    case .sub:
      name = MPVOption.TrackSelection.sid
    case .secondSub:
      name = MPVOption.Subtitles.secondarySid
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
    mpvController.setDouble(MPVOption.PlaybackControl.speed, realSpeed)
    info.playSpeed = speed
  }
  
  func setVideoAspect(_ aspect: String) {
    if AppData.aspectRegex.matches(aspect) {
      mpvController.setString(MPVProperty.videoAspect, aspect)
      info.unsureAspect = aspect
    } else {
      mpvController.setString(MPVProperty.videoAspect, "-1")
      // if not a aspect string, set aspect to default, and also the info string.
      info.unsureAspect = "Default"
    }
  }
  
  func setVideoRotate(_ degree: Int) {
    if AppData.rotations.index(of: degree)! >= 0 {
      mpvController.setInt(MPVOption.Video.videoRotate, degree)
      info.rotation = degree
    }
  }
  
  func setFlip(_ enable: Bool) {
    if enable {
      if info.flipFilter == nil {
        let vf = MPVFilter.flip()
        addVideoFilter(vf)
        info.flipFilter = vf
      }
    } else {
      if let vf = info.flipFilter {
        removeVideoFiler(vf)
        info.flipFilter = nil
      }
    }
  }
  
  func setMirror(_ enable: Bool) {
    if enable {
      if info.mirrorFilter == nil {
        let vf = MPVFilter.mirror()
        addVideoFilter(vf)
        info.mirrorFilter = vf
      }
    } else {
      if let vf = info.mirrorFilter {
        removeVideoFiler(vf)
        info.mirrorFilter = nil
      }
    }
  }
  
  func loadExternalAudioFile(_ url: URL) {
    mpvController.command([MPVCommand.audioAdd, url.path, nil])
    getTrackInfo()
    getSelectedTracks()
  }
  
  func loadExternalSubFile(_ url: URL) {
    mpvController.command([MPVCommand.subAdd, url.path, nil])
    getTrackInfo()
    getSelectedTracks()
  }
  
  func setAudioDelay(_ delay: Double) {
    mpvController.setDouble(MPVOption.Audio.audioDelay, delay)
    info.audioDelay = delay
  }
  
  func setSubDelay(_ delay: Double) {
    mpvController.setDouble(MPVOption.Subtitles.subDelay, delay)
    info.subDelay = delay
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
  
  func addVideoFilter(_ filter: MPVFilter) {
    mpvController.command([MPVCommand.vf, "add", filter.stringFormat, nil])
  }
  
  func removeVideoFiler(_ filter: MPVFilter) {
    mpvController.command([MPVCommand.vf, "del", filter.stringFormat, nil])
  }
  
  /** Scale is a double value in [-100, -1] + [1, 100] */
  func setSubScale(_ scale: Double) {
    if scale > 0 {
      mpvController.setDouble(MPVOption.Subtitles.subScale, scale)
    } else {
      mpvController.setDouble(MPVOption.Subtitles.subScale, -scale)
    }
  }
  
  func setSubTextColor(_ colorString: String) {
    mpvController.setString("options/" + MPVOption.OSD.subTextColor, colorString)
  }
  
  func setSubTextBgColor(_ colorString: String) {
    mpvController.setString("options/" + MPVOption.OSD.subTextBackColor, colorString)
  }
  
  // MARK: - Other
  
  /** This function is called right after file loaded. Should load all meta info here. */
  func fileLoaded() {
    guard let vwidth = info.videoWidth, let vheight = info.videoHeight else {
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
    guard let dwidth = info.displayWidth, let dheight = info.displayHeight else {
      Utility.fatal("Cannot get video width and height")
      return
    }
    if dwidth != 0 && dheight != 0 {
      DispatchQueue.main.sync {
        mainWindow.adjustFrameByVideoSize(dwidth, dheight)
      }
    }
  }
  
  // MARK: - Sync with UI in MainWindow
  
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
      let pause = mpvController.getFlag(MPVOption.PlaybackControl.pause)
      info.isPaused = pause
      DispatchQueue.main.async {
        self.mainWindow.updatePlayButtonState(pause ? NSOffState : NSOnState)
      }
    case .MuteButton:
      let mute = mpvController.getFlag(MPVOption.Audio.mute)
      DispatchQueue.main.async {
        self.mainWindow.muteButton.state = mute ? NSOnState : NSOffState
      }
    case .chapterList:
      DispatchQueue.main.async {
        // this should avoid sending reload when table view is not ready
        if self.mainWindow.sideBarStatus == .playlist {
          self.mainWindow.playlistView.chapterTableView.reloadData()
        }
      }
    }
  }
  
  // MARK: - Getting info
  
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
    info.aid = mpvController.getInt(MPVOption.TrackSelection.aid)
    info.vid = mpvController.getInt(MPVOption.TrackSelection.vid)
    info.sid = mpvController.getInt(MPVOption.TrackSelection.sid)
    info.secondSid = mpvController.getInt(MPVOption.Subtitles.secondarySid)
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
