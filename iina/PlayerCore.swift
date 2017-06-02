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
  let backgroundQueue: DispatchQueue = DispatchQueue(label: "IINAPlayerCoreTask")

  var mainWindow: MainWindowController?
  lazy var mpvController: MPVController = MPVController()

  lazy var info: PlaybackInfo = PlaybackInfo()

  var syncPlayTimeTimer: Timer?

  var displayOSD: Bool = true

  var isMpvTerminated: Bool = false

  // test seeking
  var triedUsingExactSeekForCurrentFile: Bool = false
  var useExactSeekForCurrentFile: Bool = true

  // need enter fullscreen for nect file
  var needEnterFullScreenForNextMedia: Bool = true

  static var keyBindings: [String: KeyMapping] = [:]

  // MARK: - Control commands

  // Open a file
  func openFile(_ url: URL?) {
    guard let path = url?.path else {
      Utility.log("Error: empty file path or url")
      return
    }
    openMainWindow(path: path, url: url!, isNetwork: false)
  }

  func openURL(_ url: URL) {
    let path = url.absoluteString
    openMainWindow(path: path, url: url, isNetwork: true)
  }

  func openURLString(_ str: String) {
    guard let str = str.addingPercentEncoding(withAllowedCharacters: .urlAllowed),
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
    // clear currentFolder since playlist is cleared, so need to auto-load again in playerCore#fileStarted
    info.currentFolder = nil
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

    // load keybindings
    let userConfigs = UserDefaults.standard.dictionary(forKey: Preference.Key.inputConfigs)
    let iinaDefaultConfPath = PrefKeyBindingViewController.defaultConfigs["IINA Default"]!
    var inputConfPath = iinaDefaultConfPath
    if let confFromUd = UserDefaults.standard.string(forKey: Preference.Key.currentInputConfigName) {
      if let currentConfigFilePath = Utility.getFilePath(Configs: userConfigs, forConfig: confFromUd, showAlert: false) {
        inputConfPath = currentConfigFilePath
      }
    }
    let mapping = KeyMapping.parseInputConf(at: inputConfPath) ?? KeyMapping.parseInputConf(at: iinaDefaultConfPath)!
    PlayerCore.keyBindings = [:]
    mapping.forEach { PlayerCore.keyBindings[$0.key.lowercased()] = $0 }

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
    sendOSD(.screenShot)
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
    sendOSD(.abLoop(info.abLoopStatus))
  }

  func toggleFileLoop() {
    let isLoop = mpvController.getFlag(MPVOption.PlaybackControl.loopFile)
    mpvController.setFlag(MPVOption.PlaybackControl.loopFile, !isLoop)
  }

  func togglePlaylistLoop() {
    let loopStatus = mpvController.getString(MPVOption.PlaybackControl.loopPlaylist)
    let isLoop = (loopStatus == "inf" || loopStatus == "force")
    mpvController.setString(MPVOption.PlaybackControl.loopPlaylist, isLoop ? "no" : "inf")
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
          Utility.showAlert("unsupported_audio")
        }
      }
    }
  }

  func loadExternalSubFile(_ url: URL) {
    guard !(info.subTracks.contains { $0.externalFilename == url.path }) else { return }

    mpvController.command(.subAdd, args: [url.path], checkError: false) { code in
      if code < 0 {
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_sub")
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

  struct GeometryDef {
    var x: String?, y: String?, w: String?, h: String?, xSign: String?, ySign: String?
  }

  func getGeometry() -> GeometryDef? {
    let geometry = mpvController.getString(MPVOption.Window.geometry) ?? ""
    // guard option value
    guard !geometry.isEmpty else { return nil }
    // match the string, replace empty group by nil
    let captures: [String?] = Regex.geometry.captures(in: geometry).map { $0.isEmpty ? nil : $0 }
    // guard matches
    guard captures.count == 10 else { return nil }
    // return struct
    return GeometryDef(x: captures[7],
                       y: captures[9],
                       w: captures[2],
                       h: captures[4],
                       xSign: captures[6],
                       ySign: captures[8])
  }

  // MARK: - Listeners

  func fileStarted() {
    info.justStartedFile = true
    info.disableOSDForFileLoading = true
    guard let path = mpvController.getString(MPVProperty.path) else { return }
    info.currentURL = URL(fileURLWithPath: path)
    backgroundQueue.async {
      // add files in same folder
      if self.ud.bool(forKey: Preference.Key.playlistAutoAdd) {
        self.autoLoadFilesInCurrentFolder()
      }
      // auto load matched subtitles
      if let matchedSubs = self.info.matchedSubs[path] {
        for sub in matchedSubs {
          self.loadExternalSubFile(sub)
        }
        // set sub to the first one
        self.setTrack(1, forType: .sub)
      }
    }
  }

  /** This function is called right after file loaded. Should load all meta info here. */
  func fileLoaded() {
    guard let mw = mainWindow else {
      Utility.fatal("Window is nil at fileLoaded")
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
      // whether enter full screen
      if needEnterFullScreenForNextMedia {
        if ud.bool(forKey: Preference.Key.fullScreenWhenOpen) && !mw.isInFullScreen {
          mw.toggleWindowFullScreen()
        }
        // only enter fullscreen for first file
        needEnterFullScreenForNextMedia = false
      }
    }
    // add to history
    if let url = info.currentURL {
      let duration = info.videoDuration ?? .zero
      HistoryController.shared.add(url, duration: duration.second)
      if ud.bool(forKey: Preference.Key.recordRecentFiles) && ud.bool(forKey: Preference.Key.trackAllFilesInRecentOpenMenu) {
        NSDocumentController.shared().noteNewRecentDocumentURL(url)
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

  func playbackRestarted() {
    DispatchQueue.main.async {
      Timer.scheduledTimer(timeInterval: TimeInterval(0.2), target: self, selector: #selector(self.reEnableOSDAfterFileLoading), userInfo: nil, repeats: false)
    }
  }

  @objc
  private func reEnableOSDAfterFileLoading() {
    info.disableOSDForFileLoading = false
  }

  /// Add files in the same folder to playlist.
  private func autoLoadFilesInCurrentFolder() {
    guard let folder = info.currentURL?.deletingLastPathComponent(), folder.isFileURL else { return }

    // don't load file if user didn't switch folder
    guard folder.path != info.currentFolder?.path else { return }
    info.currentFolder = folder

    // search subs
    let fm = FileManager.default
    let searchOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
    let subExts = Utility.supportedFileExt[.sub]!
    var subDirs: [URL] = []

    // search subs in current directory
    guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: searchOptions) else { return }

    // search subs in other directories
    let rawUserDefinedSearchPaths = ud.string(forKey: Preference.Key.subAutoLoadSearchPath) ?? "./*"
    let userDefinedSearchPaths = rawUserDefinedSearchPaths.components(separatedBy: ":").filter { !$0.isEmpty }
    for path in userDefinedSearchPaths {
      var p = path
      // handle `~`
      if path.hasPrefix("~") {
        p = NSString(string: path).expandingTildeInPath
      }
      if path.hasSuffix("/") { p.deleteLast(1) }
      // only check wildcard at the end
      let hasWildcard = path.hasSuffix("/*")
      if hasWildcard { p.deleteLast(2) }
      // handle absolute paths
      let pathURL = path.hasPrefix("/") || path.hasPrefix("~") ? URL(fileURLWithPath: p, isDirectory: true) : folder.appendingPathComponent(p, isDirectory: true)
      // handle wildcards
      if hasWildcard {
        // append all sub dirs
        if let contents = try? fm.contentsOfDirectory(at: pathURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
          if #available(OSX 10.11, *) {
            subDirs.append(contentsOf: contents.filter { $0.hasDirectoryPath })
          } else {
            subDirs.append(contentsOf: contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false })
          }
        }
      } else {
        subDirs.append(pathURL)
      }
    }

    // group by extension
    var groups: [MPVTrack.TrackType: [FileInfo]] = [.video: [], .audio: [], .sub: []]
    let allTypes: [MPVTrack.TrackType] = [.video, .audio, .sub]
    for file in files {
      let fileInfo = FileInfo(file)
      guard let mediaType = allTypes.first(where: { Utility.supportedFileExt[$0]!.contains(fileInfo.ext) }) else { continue }
      groups[mediaType]!.append(fileInfo)
    }

    // natural sort
    groups[.video]!.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }

    // get all possible sub files
    var subtitles = groups[.sub]!
    for subDir in subDirs {
      if let contents = try? fm.contentsOfDirectory(at: subDir, includingPropertiesForKeys: nil, options: searchOptions) {
        subtitles.append(contentsOf: contents.flatMap { subExts.contains($0.pathExtension) ? FileInfo($0) : nil })
      }
    }
    info.currentSubsInfo = subtitles

    // add files to playlist
    var addedCurrentVideo = false
    for video in groups[.video]! {
      // add to playlist
      if video.url.path == info.currentURL!.path {
        addedCurrentVideo = true
      } else if addedCurrentVideo {
        addToPlaylist(video.path)
      } else {
        let count = mpvController.getInt(MPVProperty.playlistCount)
        let current = mpvController.getInt(MPVProperty.playlistPos)
        addToPlaylist(video.path)
        playlistMove(count, to: current)
      }
    }
    for audio in groups[.audio]! {
      addToPlaylist(audio.path)
    }
    NotificationCenter.default.post(name: Constants.Noti.playlistChanged, object: nil)

    // get auto load option
    let subAutoLoadOption: Preference.IINAAutoLoadAction = Preference.IINAAutoLoadAction(rawValue: ud.integer(forKey: Preference.Key.subAutoLoadIINA)) ?? .iina
    guard subAutoLoadOption != .disabled else { return }

    // group video files
    let series = FileGroup.group(files: groups[.video]!)
    let videoPrefixes = series.flatten()

    // group sub files
    let subPrefiexes = FileGroup.group(files: subtitles).flatten()

    // match video and sub groups (series)
    var prefixDistance: [String: [String: UInt]] = [:]
    var closestVideoForSub: [String: String] = [:]
    for (sp, _) in subPrefiexes {
      prefixDistance[sp] = [:]
      var minDist = UInt.max
      var minVideo = ""
      for (vp, vl) in videoPrefixes {
        guard vl.count > 2 else { continue }
        let dist = ObjcUtils.levDistance(vp, and: sp)
        prefixDistance[sp]![vp] = dist
        if dist < minDist {
          minDist = dist
          minVideo = vp
        }
      }
      closestVideoForSub[sp] = minVideo
    }
    var matchedPrefixes: [String: String] = [:]  // video: sub
    for (vp, vl) in videoPrefixes {
      guard vl.count > 2 else { continue }
      var minDist = UInt.max
      var minSub = ""
      for (sp, _) in subPrefiexes {
        let dist = prefixDistance[sp]![vp]!
        if dist < minDist {
          minDist = dist
          minSub = sp
        }
      }
      if closestVideoForSub[minSub] == vp {
        matchedPrefixes[vp] = minSub
      }
    }

    var unmatchedVideos: [FileInfo] = []

    // match sub for video files
    for video in groups[.video]! {
      var matchedSubs = Set<FileInfo>()
      // match video and sub if both are the closest one to each other
      if subAutoLoadOption.shouldLoadSubsMatchedByIINA() {
        // is in series
        if !video.prefix.isEmpty, let matchedSubPrefix = matchedPrefixes[video.prefix] {
          // find sub with same name
          subtitles.forEach { sub in
            guard let vn = video.nameInSeries, let sn = sub.nameInSeries else { return }
            var nameMatched: Bool
            if let vnInt = Int(vn), let snInt = Int(sn) {
              nameMatched = vnInt == snInt
            } else {
              nameMatched = vn == sn
            }
            if nameMatched {
              video.relatedSubs.append(sub)
              if sub.prefix == matchedSubPrefix {
                info.matchedSubs.safeAppend(sub.url, for: video.path)
                sub.isMatched = true
                matchedSubs.insert(sub)
              }
            }
          }
        }
      }
      // add subs that contains video name
      if subAutoLoadOption.shouldLoadSubsContainingVideoName() {
        subtitles
          .filter { $0.filename.contains(video.filename) }
          .forEach { sub in
            info.matchedSubs.safeAppend(sub.url, for: video.path)
            sub.isMatched = true
            matchedSubs.insert(sub)
          }
      }
      // if no match
      if matchedSubs.isEmpty {
        unmatchedVideos.append(video)
      }
      // move the sub to front if it contains priority strings
      if let priorString = ud.string(forKey: Preference.Key.subAutoLoadPriorityString), !matchedSubs.isEmpty {
        let stringList = priorString
          .components(separatedBy: ",")
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
        // find the min occurance count first
        var minOccurances = Int.max
        matchedSubs.forEach { sub in
          sub.priorityStringOccurances = stringList.reduce(0, { $0 + sub.filename.countOccurances(of: $1, in: nil) })
          if sub.priorityStringOccurances < minOccurances {
            minOccurances = sub.priorityStringOccurances
          }
        }
        matchedSubs
          .filter { $0.priorityStringOccurances > minOccurances }  // eliminate false positives in filenames
          .flatMap { info.matchedSubs[video.path]!.index(of: $0.url) }  // get index
          .forEach {  // move the sub with index to first
            let s = info.matchedSubs[video.path]!.remove(at: $0)
            info.matchedSubs[video.path]!.insert(s, at: 0)
          }
      }
    }

    info.currentVideosInfo = groups[.video]!
    NotificationCenter.default.post(name: Constants.Noti.playlistChanged, object: nil)

    // match unmatched subs and videos
    let unmatchedSubs = subtitles.filter { !$0.isMatched }
    if unmatchedSubs.count > 0 && unmatchedVideos.count > 0 {
      // calculate edit distance
      for sub in unmatchedSubs {
        var minDistToVideo: UInt = .max
        for video in unmatchedVideos {
          let dist = ObjcUtils.levDistance(video.prefix, and: sub.prefix) + ObjcUtils.levDistance(video.suffix, and: sub.suffix)
          sub.dist[video] = dist
          video.dist[sub] = dist
          if dist < minDistToVideo { minDistToVideo = dist }
        }
        sub.minDist = groups[.video]!.filter { sub.dist[$0] == minDistToVideo }
      }

      // match them
      for video in unmatchedVideos {
        let minDistToSub = video.dist.reduce(UInt.max, { min($0.0, $0.1.value) })
        unmatchedSubs
          .filter { video.dist[$0]! == minDistToSub && $0.minDist.contains(video) }
          .forEach {
            info.matchedSubs.safeAppend($0.url, for: video.path)
          }
      }
      NotificationCenter.default.post(name: Constants.Noti.playlistChanged, object: nil)
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
        if #available(OSX 10.12.2, *) {
          mw.updateTouchBarPlayBtn()
        }
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

    if info.disableOSDForFileLoading {
      guard case .fileStart = osd else {
        return
      }
    }

    DispatchQueue.main.async {
      mw.displayOSD(osd)
    }
  }

  func errorOpeningFileAndCloseMainWindow() {
    DispatchQueue.main.async {
      Utility.showAlert("error_open")
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
