//
//  PlayerCore.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class PlayerCore: NSObject {

  static let shared = PlayerCore()

  unowned let ud: UserDefaults = UserDefaults.standard

  var mainWindow: MainWindowController?
  lazy var mpvController: MPVController = MPVController()

  let supportedSubtitleFormat: [String] = ["utf", "utf8", "utf-8", "idx", "sub", "srt",
                                           "smi", "rt", "txt", "ssa", "aqt", "jss",
                                           "js", "ass", "mks", "vtt", "sup"]

  lazy var info: PlaybackInfo = PlaybackInfo()

  var syncPlayTimeTimer: Timer?

  var displayOSD: Bool = true

  var isMpvTerminated: Bool = false

  // test seeking
  var triedUsingExactSeekForCurrentFile: Bool = false
  var useExactSeekForCurrentFile: Bool = true

  // need enter fullscreen for nect file
  var needEnterFullScreenForNextMedia: Bool = true

  // MARK: - Control commands

  // Open a file
  func openFile(_ url: URL?) {
    guard let path = url?.path else {
      Utility.log("Error: empty file path or url")
      return
    }
    openMainWindow(path: path, url: url!, isNetwork: false)
  }

  func openURLString(_ str: String) {
    // FIXME: Technically, we shouldn't be percent encoding the whole URL with
    // one character set.
    guard let str = str.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
      let url = URL(string: str) else {
        return
    }
    openMainWindow(path: str, url: url, isNetwork: true)
  }

  private func openMainWindow(path: String, url: URL, isNetwork: Bool) {
    if mainWindow == nil || !mainWindow!.isWindowLoaded {
      mainWindow = nil
      mainWindow = MainWindowController()
    }
    info.currentURL = url
    info.isNetworkResource = isNetwork
     mainWindow!.showWindow(nil)
     mainWindow!.windowDidOpen()
    // Send load file command
    info.fileLoading = true
    info.justOpenedFile = true
    mpvController.command(.loadfile, args: [path])
  }

  func startMPV() {
    // set path for youtube-dl
    let oldPath = String(cString: getenv("PATH")!)
    var path = Utility.exeDirURL.path + ":" + oldPath
    if let customYtdlPath = ud.string(forKey: Preference.Key.ytdlSearchPath), !customYtdlPath.isEmpty {
      path = customYtdlPath + ":" + path
    }
    setenv("PATH", path, 1)

    // set http proxy
    if let proxy = ud.string(forKey: Preference.Key.httpProxy), !proxy.isEmpty {
      setenv("http_proxy", "http://" + proxy, 1)
    }

    mpvController.mpvInit()
  }

  func startMPVOpenGLCB(_ videoView: VideoView) {
    let mpvGLContext = mpvController.mpvInitCB()
    videoView.mpvGLContext = OpaquePointer(mpvGLContext)
  }

  // unload main window video view
  func unloadMainWindowVideoView() {
    guard let mw = mainWindow, mw.isWindowLoaded else { return }
    mw.videoView.uninit()
  }

  // Terminate mpv
  func terminateMPV(sendQuit: Bool = true) {
    guard !isMpvTerminated else { return }
    savePlaybackPosition()
    invalidateTimer()
    unloadMainWindowVideoView()
    if sendQuit {
      mpvController.mpvQuit()
    }
    isMpvTerminated = true
  }

  // invalidate timer
  func invalidateTimer() {
    syncPlayTimeTimer?.invalidate()
  }

  // MARK: - MPV commands

  /** Pause / resume. Reset speed to 0 when pause. */
  func togglePause(_ set: Bool?) {
    if let setPause = set {
      // if paused by EOF, replay the video.
      if !setPause {
        if mpvController.getFlag(MPVProperty.eofReached) {
          seek(absoluteSecond: 0)
        }
      }
      mpvController.setFlag(MPVOption.PlaybackControl.pause, setPause)
    } else {
      if (info.isPaused) {
        if mpvController.getFlag(MPVProperty.eofReached) {
          seek(absoluteSecond: 0)
        }
        mpvController.setFlag(MPVOption.PlaybackControl.pause, false)
      } else {
        mpvController.setFlag(MPVOption.PlaybackControl.pause, true)
      }
    }
  }

  func stop() {
    mpvController.command(.stop)
    invalidateTimer()
  }

  func toogleMute(_ set: Bool?) {
    let newState = set ?? !mpvController.getFlag(MPVOption.Audio.mute)
    mpvController.setFlag(MPVOption.Audio.mute, newState)
  }

  func seek(percent: Double, forceExact: Bool = false) {
    let useExact = forceExact ? true : ud.bool(forKey: Preference.Key.useExactSeek)
    let seekMode = useExact ? "absolute-percent+exact" : "absolute-percent"
    mpvController.command(.seek, args: ["\(percent)", seekMode], checkError: false)
  }

  func seek(relativeSecond: Double, option: Preference.SeekOption) {
    switch option {

    case .relative:
      mpvController.command(.seek, args: ["\(relativeSecond)", "relative"], checkError: false)

    case .extract:
      mpvController.command(.seek, args: ["\(relativeSecond)", "relative+exact"], checkError: false)

    case .auto:
      // for each file , try use exact and record interval first
      if !triedUsingExactSeekForCurrentFile {
        mpvController.recordedSeekTimeListener = { [unowned self] interval in
          // if seek time < 0.05, then can use exact
          self.useExactSeekForCurrentFile = interval < 0.05
        }
        mpvController.needRecordSeekTime = true
        triedUsingExactSeekForCurrentFile = true
      }
      let seekMode = useExactSeekForCurrentFile ? "relative+exact" : "relative"
      mpvController.command(.seek, args: ["\(relativeSecond)", seekMode], checkError: false)

    }
  }

  func seek(absoluteSecond: Double) {
    mpvController.command(.seek, args: ["\(absoluteSecond)", "absolute+exact"])
  }

  func frameStep(backwards: Bool) {
    if backwards {
      mpvController.command(.frameBackStep)
    } else {
      mpvController.command(.frameStep)
    }
  }

  func screenShot() {
    let option = ud.bool(forKey: Preference.Key.screenshotIncludeSubtitle) ? "subtitles" : "video"
    mpvController.command(.screenshot, args: [option])
  }

  func abLoop() {
    // may subject to change
    mpvController.command(.abLoop)
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

  func toggleFileLoop() {
    let isLoop = mpvController.getFlag(MPVOption.PlaybackControl.loopFile)
    mpvController.setFlag(MPVOption.PlaybackControl.loopFile, !isLoop)
  }

  func togglePlaylistLoop() {
    let loopStatus = mpvController.getString(MPVOption.PlaybackControl.loop)
    let isLoop = (loopStatus == "inf" || loopStatus == "force")
    mpvController.setString(MPVOption.PlaybackControl.loop, isLoop ? "no" : "inf")
  }

  func toggleShuffle() {
    mpvController.command(.playlistShuffle)
    NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
  }

  func setVolume(_ volume: Double, constrain: Bool = true) {
    let constrainedVolume = volume.constrain(min: 0, max: 100)
    let appliedVolume = constrain ? constrainedVolume : volume
    info.volume = appliedVolume
    mpvController.setDouble(MPVOption.Audio.volume, appliedVolume)
    ud.set(constrainedVolume, forKey: Preference.Key.softVolume)
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

  /** Set speed. */
  func setSpeed(_ speed: Double) {
    mpvController.setDouble(MPVOption.PlaybackControl.speed, speed)
    info.playSpeed = speed
  }

  func setVideoAspect(_ aspect: String) {
    if Regex.aspect.matches(aspect) {
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
        if addVideoFilter(vf) {
          info.flipFilter = vf
        }
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
        if addVideoFilter(vf) {
          info.mirrorFilter = vf
        }
      }
    } else {
      if let vf = info.mirrorFilter {
        removeVideoFiler(vf)
        info.mirrorFilter = nil
      }
    }
  }

  func toggleDeinterlace(_ enable: Bool) {
    mpvController.setFlag(MPVOption.Video.deinterlace, enable)
  }

  enum VideoEqualizerType {
    case brightness, contrast, saturation, gamma, hue
  }

  func setVideoEqualizer(forOption option: VideoEqualizerType, value: Int) {
    let optionName: String
    switch option {
    case .brightness:
      optionName = MPVOption.Equalizer.brightness
    case .contrast:
      optionName = MPVOption.Equalizer.contrast
    case .saturation:
      optionName = MPVOption.Equalizer.saturation
    case .gamma:
      optionName = MPVOption.Equalizer.gamma
    case .hue:
      optionName = MPVOption.Equalizer.hue
    }
    mpvController.command(.set, args: [optionName, value.toStr()])
  }

  func loadExternalAudioFile(_ url: URL) {
    mpvController.command(.audioAdd, args: [url.path], checkError: false) { code in
      if code < 0 {
        DispatchQueue.main.async {
          Utility.showAlert(message: "Unsupported external audio file.")
        }
      }
    }
  }

  func loadExternalSubFile(_ url: URL) {
    guard !(info.subTracks.contains { $0.externalFilename == url.path }) else { return }

    mpvController.command(.subAdd, args: [url.path], checkError: false) { code in
      if code < 0 {
        DispatchQueue.main.async {
          Utility.showAlert(message: "Unsupported external subtitle.")
        }
      }
    }
  }

  func setAudioDelay(_ delay: Double) {
    mpvController.setDouble(MPVOption.Audio.audioDelay, delay)
  }

  func setSubDelay(_ delay: Double) {
    mpvController.setDouble(MPVOption.Subtitles.subDelay, delay)
  }

  func addToPlaylist(_ path: String) {
    mpvController.command(.loadfile, args: [path, "append"])
  }

  func playlistMove(_ from: Int, to: Int) {
    mpvController.command(.playlistMove, args: ["\(from)", "\(to)"])
  }

  func playlistRemove(_ index: Int) {
    mpvController.command(.playlistRemove, args: [index.toStr()])
  }

  func clearPlaylist() {
    mpvController.command(.playlistClear)
  }

  func removeFromPlaylist(index: Int) {
    mpvController.command(.playlistRemove, args: ["\(index)"])
  }

  func playFile(_ path: String) {
    info.justOpenedFile = true
    mpvController.command(.loadfile, args: [path, "replace"])
    getPLaylist()
  }

  func playFileInPlaylist(_ pos: Int) {
    mpvController.setInt(MPVProperty.playlistPos, pos)
    getPLaylist()
  }

  func navigateInPlaylist(nextOrPrev: Bool) {
    mpvController.command(nextOrPrev ? .playlistNext : .playlistPrev)
  }

  func playChapter(_ pos: Int) {
    let chapter = info.chapters[pos]
    mpvController.command(.seek, args: ["\(chapter.time.second)", "absolute"])
    // need to update time pos
    syncUITime()
  }

  func setCrop(fromString str: String) {
    let vwidth = info.videoWidth!
    let vheight = info.videoHeight!
    if let aspect = Aspect(string: str) {
      let cropped = NSMakeSize(CGFloat(vwidth), CGFloat(vheight)).crop(withAspect: aspect)
      let vf = MPVFilter.crop(w: Int(cropped.width), h: Int(cropped.height), x: nil, y: nil)
      setCrop(fromFilter: vf)
      // warning! may should not update it here
      info.unsureCrop = str
      info.cropFilter = vf
    } else {
      if let filter = info.cropFilter {
        removeVideoFiler(filter)
        info.unsureCrop = "None"
      }
    }
  }

  func setCrop(fromFilter filter: MPVFilter) {
    filter.label = "iina_crop"
    if addVideoFilter(filter) {
      info.cropFilter = filter
    }
  }

  func setAudioEq(fromFilter filter: MPVFilter) {
    filter.label = "iina_aeq"
    addAudioFilter(filter)
    info.audioEqFilter = filter
  }

  func removeAudioEqFilter() {
    if let prevFilter = info.audioEqFilter {
      removeAudioFilter(prevFilter)
      info.audioEqFilter = nil
    }
  }

  func addVideoFilter(_ filter: MPVFilter) -> Bool {
    var result = true
    mpvController.command(.vf, args: ["add", filter.stringFormat], checkError: false) { result = $0 >= 0 }
    return result
  }

  func removeVideoFiler(_ filter: MPVFilter) {
    mpvController.command(.vf, args: ["del", filter.stringFormat], checkError: false)
  }

  func addAudioFilter(_ filter: MPVFilter) {
    mpvController.command(.af, args: ["add", filter.stringFormat], checkError: false)
  }

  func removeAudioFilter(_ filter: MPVFilter) {
    mpvController.command(.af, args: ["del", filter.stringFormat], checkError: false)
  }

  func getAudioDevices() -> [[String: String]] {
    let raw = mpvController.getNode(MPVProperty.audioDeviceList)
    if let list = raw as? [[String: String]] {
      return list
    } else {
      return []
    }
  }

  func setAudioDevice(_ name: String) {
    mpvController.setString(MPVProperty.audioDevice, name)
  }

  /** Scale is a double value in [-100, -1] + [1, 100] */
  func setSubScale(_ scale: Double) {
    if scale > 0 {
      mpvController.setDouble(MPVOption.Subtitles.subScale, scale)
    } else {
      mpvController.setDouble(MPVOption.Subtitles.subScale, -scale)
    }
  }

  func setSubPos(_ pos: Int) {
    mpvController.setInt(MPVOption.Subtitles.subPos, pos)
  }

  func setSubTextColor(_ colorString: String) {
    mpvController.setString("options/" + MPVOption.Subtitles.subColor, colorString)
  }

  func setSubTextSize(_ size: Double) {
    mpvController.setDouble("options/" + MPVOption.Subtitles.subFontSize, size)
  }

  func setSubTextBold(_ bold: Bool) {
    mpvController.setFlag("options/" + MPVOption.Subtitles.subBold, bold)
  }

  func setSubTextBorderColor(_ colorString: String) {
    mpvController.setString("options/" + MPVOption.Subtitles.subBorderColor, colorString)
  }

  func setSubTextBorderSize(_ size: Double) {
    mpvController.setDouble("options/" + MPVOption.Subtitles.subBorderSize, size)
  }

  func setSubTextBgColor(_ colorString: String) {
    mpvController.setString("options/" + MPVOption.Subtitles.subBackColor, colorString)
  }

  func setSubEncoding(_ encoding: String) {
    mpvController.setString(MPVOption.Subtitles.subCodepage, encoding)
    info.subEncoding = encoding
  }

  func setSubFont(_ font: String) {
    mpvController.setString(MPVOption.Subtitles.subFont, font)
  }

  func execKeyCode(_ code: String) {
    mpvController.command(.keypress, args: [code], checkError: false) { errCode in
      if errCode < 0 {
        Utility.log("Error when executing key code (\(errCode))")
      }
    }
  }

  func savePlaybackPosition() {
    mpvController.command(.writeWatchLaterConfig)
  }

  // MARK: - Other

  func fileStarted() {
    info.justStartedFile = true
  }

  /** This function is called right after file loaded. Should load all meta info here. */
  func fileLoaded() {
    guard let mw = mainWindow else {
      Utility.fatal("Window is nil at fileLoaded")
    }
    guard let vwidth = info.videoWidth, let vheight = info.videoHeight else {
      Utility.fatal("Cannot get video width and height")
    }
    invalidateTimer()
    triedUsingExactSeekForCurrentFile = false
    info.fileLoading = false
    info.haveDownloadedSub = false
    DispatchQueue.main.sync {
      self.getTrackInfo()
      self.getSelectedTracks()
      self.getPLaylist()
      self.getChapters()
      syncPlayTimeTimer = Timer.scheduledTimer(timeInterval: TimeInterval(AppData.getTimeInterval),
                                               target: self, selector: #selector(self.syncUITime), userInfo: nil, repeats: true)
      mw.updateTitle()
      if #available(OSX 10.12.2, *) {
        mw.setupTouchBarUI()
      }
      mw.adjustFrameByVideoSize(vwidth, vheight)
      // whether enter full screen
      if needEnterFullScreenForNextMedia {
        if ud.bool(forKey: Preference.Key.fullScreenWhenOpen) && !mw.isInFullScreen {
          mw.toggleWindowFullScreen()
        }
        // only enter fullscreen for first file
        needEnterFullScreenForNextMedia = false
      }
    }
    
    NotificationCenter.default.post(Notification(name: Constants.Noti.fileLoaded))
  }

  func notifyMainWindowVideoSizeChanged() {
    guard let mw = mainWindow else { return }
    guard let dwidth = info.displayWidth, let dheight = info.displayHeight else {
      Utility.fatal("Cannot get video width and height")
    }
    if dwidth != 0 && dheight != 0 {
      DispatchQueue.main.sync {
        mw.adjustFrameByVideoSize(dwidth, dheight)
      }
    }
  }

  // MARK: - Sync with UI in MainWindow

  // difficult to use option set
  enum SyncUIOption {
    case time
    case timeAndCache
    case playButton
    case volume
    case muteButton
    case chapterList
    case playlist
  }

  func syncUITime() {
    if info.isNetworkResource {
      syncUI(.timeAndCache)
    } else {
      syncUI(.time)
    }
  }

  func syncUI(_ option: SyncUIOption) {
    // if window not loaded, ignore
    guard let mw = mainWindow, mw.isWindowLoaded else { return }

    switch option {
    case .time:
      let time = mpvController.getDouble(MPVProperty.timePos)
      info.videoPosition = VideoTime(time)
      DispatchQueue.main.async {
        mw.updatePlayTime(withDuration: false, andProgressBar: true)
      }

    case .timeAndCache:
      let time = mpvController.getDouble(MPVProperty.timePos)
      info.videoPosition = VideoTime(time)
      info.pausedForCache = mpvController.getFlag(MPVProperty.pausedForCache)
      info.cacheSize = mpvController.getInt(MPVProperty.cacheSize)
      info.cacheUsed = mpvController.getInt(MPVProperty.cacheUsed)
      info.cacheSpeed = mpvController.getInt(MPVProperty.cacheSpeed)
      info.cacheTime = mpvController.getInt(MPVProperty.demuxerCacheTime)
      info.bufferingState = mpvController.getInt(MPVProperty.cacheBufferingState)
      DispatchQueue.main.async {
        mw.updatePlayTime(withDuration: true, andProgressBar: true)
        mw.updateNetworkState()
      }

    case .playButton:
      let pause = mpvController.getFlag(MPVOption.PlaybackControl.pause)
      info.isPaused = pause
      DispatchQueue.main.async {
        mw.updatePlayButtonState(pause ? NSOffState : NSOnState)
      }

    case .volume:
      DispatchQueue.main.async {
        mw.updateVolume()
      }

    case .muteButton:
      let mute = mpvController.getFlag(MPVOption.Audio.mute)
      DispatchQueue.main.async {
        mw.muteButton.state = mute ? NSOnState : NSOffState
      }

    case .chapterList:
      DispatchQueue.main.async {
        // this should avoid sending reload when table view is not ready
        if mw.sideBarStatus == .playlist {
          mw.playlistView.chapterTableView.reloadData()
        }
      }

    case .playlist:
      DispatchQueue.main.async {
        if mw.sideBarStatus == .playlist {
          mw.playlistView.playlistTableView.reloadData()
        }
      }
    }
  }

  func sendOSD(_ osd: OSDMessage) {
    // querying `mainWindow.isWindowLoaded` will initialize mainWindow unexpectly
    guard let mw = mainWindow, mw.isWindowLoaded else { return }

    DispatchQueue.main.async {
      mw.displayOSD(osd)
    }
  }

  func errorOpeningFileAndCloseMainWindow() {
    DispatchQueue.main.async {
      Utility.showAlert(message: "Cannot open file or stream!")
      self.mainWindow?.close()
    }
  }

  func closeMainWindow() {
    DispatchQueue.main.async {
      self.mainWindow?.close()
    }
  }


  // MARK: - Getting info

  func getTrackInfo() {
    info.audioTracks.removeAll(keepingCapacity: true)
    info.videoTracks.removeAll(keepingCapacity: true)
    info.subTracks.removeAll(keepingCapacity: true)
    let trackCount = mpvController.getInt(MPVProperty.trackListCount)
    for index in 0..<trackCount {
      // get info for each track
      guard let trackType = mpvController.getString(MPVProperty.trackListNType(index)) else { continue }
      let track = MPVTrack(id: mpvController.getInt(MPVProperty.trackListNId(index)),
                           type: MPVTrack.TrackType(rawValue: trackType)!,
                           isDefault: mpvController.getFlag(MPVProperty.trackListNDefault(index)),
                           isForced: mpvController.getFlag(MPVProperty.trackListNForced(index)),
                           isSelected: mpvController.getFlag(MPVProperty.trackListNSelected(index)),
                           isExternal: mpvController.getFlag(MPVProperty.trackListNExternal(index)))
      track.srcId = mpvController.getInt(MPVProperty.trackListNSrcId(index))
      track.title = mpvController.getString(MPVProperty.trackListNTitle(index))
      track.lang = mpvController.getString(MPVProperty.trackListNLang(index))
      track.codec = mpvController.getString(MPVProperty.trackListNCodec(index))
      track.externalFilename = mpvController.getString(MPVProperty.trackListNExternalFilename(index))
      track.decoderDesc = mpvController.getString(MPVProperty.trackListNDecoderDesc(index))
      track.demuxFps = mpvController.getDouble(MPVProperty.trackListNDemuxFps(index))
      track.demuxChannels = mpvController.getString(MPVProperty.trackListNDemuxChannels(index))
      track.demuxSamplerate = mpvController.getInt(MPVProperty.trackListNDemuxSamplerate(index))

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

  func getSelectedTracks() {
    info.aid = mpvController.getInt(MPVOption.TrackSelection.aid)
    info.vid = mpvController.getInt(MPVOption.TrackSelection.vid)
    info.sid = mpvController.getInt(MPVOption.TrackSelection.sid)
    info.secondSid = mpvController.getInt(MPVOption.Subtitles.secondarySid)
  }

  func getPLaylist() {
    info.playlist.removeAll()
    let playlistCount = mpvController.getInt(MPVProperty.playlistCount)
    for index in 0..<playlistCount {
      let playlistItem = MPVPlaylistItem(filename: mpvController.getString(MPVProperty.playlistNFilename(index))!,
                                         isCurrent: mpvController.getFlag(MPVProperty.playlistNCurrent(index)),
                                         isPlaying: mpvController.getFlag(MPVProperty.playlistNPlaying(index)),
                                         title: mpvController.getString(MPVProperty.playlistNTitle(index)))
      info.playlist.append(playlistItem)
    }
  }

  func getChapters() {
    info.chapters.removeAll()
    let chapterCount = mpvController.getInt(MPVProperty.chapterListCount)
    if chapterCount == 0 {
      return
    }
    for index in 0..<chapterCount {
      let chapter = MPVChapter(title:     mpvController.getString(MPVProperty.chapterListNTitle(index)),
                               startTime: mpvController.getDouble(MPVProperty.chapterListNTime(index)),
                               index:     index)
      info.chapters.append(chapter)
    }
  }

}
