//
//  PlayerCore.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PlayerCore: NSObject {

  // MARK: - Multiple instances

  static let first: PlayerCore = createPlayerCore()

  static private var _lastActive: PlayerCore?

  static var lastActive: PlayerCore {
    get {
      return _lastActive ?? active
    }
    set {
      _lastActive = newValue
    }
  }

  static var active: PlayerCore {
    if let wc = NSApp.mainWindow?.windowController as? MainWindowController {
      return wc.playerCore
    } else {
      return first
    }
  }

  static var newPlayerCore: PlayerCore {
    return findIdlePlayerCore() ?? createPlayerCore()
  }

  static var activeOrNew: PlayerCore {
    if playerCores.isEmpty {
      return first
    }
    if UserDefaults.standard.bool(forKey: Preference.Key.alwaysOpenInNewWindow) {
      return newPlayerCore
    } else {
      return active
    }
  }

  static var playerCores: [PlayerCore] = []

  static private func findIdlePlayerCore() -> PlayerCore? {
    return playerCores.first { $0.info.isIdle }
  }

  static private func createPlayerCore() -> PlayerCore {
    let pc = PlayerCore()
    playerCores.append(pc)
    pc.startMPV()
    return pc
  }

  static func activeOrNewForMenuAction(isAlternative: Bool) -> PlayerCore {
    let useNew = UserDefaults.standard.bool(forKey: Preference.Key.alwaysOpenInNewWindow) != isAlternative
    return useNew ? newPlayerCore : active
  }

  // MARK: - Fields

  unowned let ud: UserDefaults = UserDefaults.standard

  /// A dispatch queue for auto load feature.
  let backgroundQueue: DispatchQueue = DispatchQueue(label: "IINAPlayerCoreTask")

  let thumbnailQueue: DispatchQueue = DispatchQueue(label: "IINAPlayerCoreThumbnailTask")

  /**
   This ticket will be increased each time before a new task being submitted to `backgroundQueue`.

   Each task holds a copy of ticket value at creation, so that a previous task will perceive and
   quit early if new tasks is awaiting.

   **See also**: 
   
   `autoLoadFilesInCurrentFolder(ticket:)`
   */
  var backgroundQueueTicket = 0

  var mainWindow: MainWindowController!
  var initialWindow: InitialWindowController!
  var miniPlayer: MiniPlayerWindowController!

  var mpvController: MPVController!

  lazy var ffmpegController: FFmpegController = {
    let controller = FFmpegController()
    controller.delegate = self
    return controller
  }()

  lazy var info: PlaybackInfo = PlaybackInfo()

  var syncPlayTimeTimer: Timer?

  var displayOSD: Bool = true

  var isMpvTerminated: Bool = false

  var isInMiniPlayer = false

  // test seeking
  var triedUsingExactSeekForCurrentFile: Bool = false
  var useExactSeekForCurrentFile: Bool = true

  // need enter fullscreen for nect file
  var needEnterFullScreenForNextMedia: Bool = true

  static var keyBindings: [String: KeyMapping] = [:]

  override init() {
    super.init()
    self.mpvController = MPVController(playerCore: self)
    self.mainWindow = MainWindowController(playerCore: self)
    self.initialWindow = InitialWindowController(playerCore: self)
    self.miniPlayer = MiniPlayerWindowController(player: self)
  }

  // MARK: - Control commands

  // Open a file
  func openURL(_ url: URL?, isNetworkResource: Bool? = nil) {
    guard let url = url else {
      Utility.log("Error: empty file path or url")
      return
    }
    let isNetwork = isNetworkResource ?? !url.isFileURL
    let path = isNetwork ? url.absoluteString : url.path
    openMainWindow(path: path, url: url, isNetwork: isNetwork)
  }

  func openURLString(_ str: String) {
    guard let str = str.addingPercentEncoding(withAllowedCharacters: .urlAllowed),
      let url = URL(string: str) else {
        return
    }
    openMainWindow(path: str, url: url, isNetwork: true)
  }

  private func openMainWindow(path: String, url: URL, isNetwork: Bool) {
    info.currentURL = url
    // clear currentFolder since playlist is cleared, so need to auto-load again in playerCore#fileStarted
    info.currentFolder = nil
    info.isNetworkResource = isNetwork
    let _ = mainWindow.window
    if !mainWindow.window!.isVisible {
      SleepPreventer.preventSleep()
    }
    initialWindow.close()
    mainWindow.showWindow(nil)
    mainWindow.windowDidOpen()
    // Send load file command
    info.fileLoading = true
    info.justOpenedFile = true
    info.currentFileIsOpenedManually = true
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
    mapping.forEach { PlayerCore.keyBindings[$0.key] = $0 }

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
    guard mainWindow.isWindowLoaded else { return }
    mainWindow.videoView.uninit()
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
    self.syncPlayTimeTimer?.invalidate()
  }

  func switchToMiniPlayer() {
    miniPlayer.showWindow(self)
    miniPlayer.updateTrack()
    let playlistView = mainWindow.playlistView.view
    // reset down shift for playlistView
    mainWindow.playlistView.downShift = 0
    // hide sidebar
    if mainWindow.sideBarStatus != .hidden {
      mainWindow.hideSideBar(animate: false)
    }
    // move playist view
    playlistView.removeFromSuperview()
    miniPlayer.playlistWrapperView.addSubview(playlistView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": playlistView])
    // hide main window
    mainWindow.window?.orderOut(self)
    isInMiniPlayer = true
  }

  func switchBackFromMiniPlayer() {
    mainWindow.playlistView.view.removeFromSuperview()
    mainWindow.window?.makeKeyAndOrderFront(self)
    // if aspect ratio is not set
    if mainWindow.window?.aspectRatio == nil {
      mainWindow.window?.aspectRatio = NSSize(width: AppData.widthWhenNoVideo, height: AppData.heightWhenNoVideo)
    }
    isInMiniPlayer = false
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
    var percent = percent
    // mpv will play next file automatically when seek to EOF.
    // the following workaround will constrain the max seek position to (video length - 1) s.
    // however, it still won't work for videos with large keyframe interval.
    if let duration = info.videoDuration?.second {
      let maxPercent = (duration - 1) / duration * 100
      percent = percent.constrain(min: 0, max: maxPercent)
    }
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

  func reloadAllSubs() {
    let currentSubName = info.currentTrack(.sub)?.externalFilename
    for subTrack in info.subTracks {
      mpvController.command(.subReload, args: ["\(subTrack.id)"], checkError: false) { code in
        if code < 0 {
          Utility.log("Error code \(code) - Failed reloading subtitles")
        }
      }
    }
    getTrackInfo()
    if let currentSub = info.subTracks.first(where: {$0.externalFilename == currentSubName}) {
      setTrack(currentSub.id, forType: .sub)
    }
    mainWindow?.quickSettingView.reloadSubtitlesData()
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

  func addToPlaylist(paths: [String], at index: Int) {
    getPlaylist()
    guard index <= info.playlist.count && index >= 0 else { return }
    let previousCount = info.playlist.count
    for path in paths {
      addToPlaylist(path)
    }
    for i in 0..<paths.count {
      playlistMove(previousCount + i, to: index + i)
    }
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
    info.currentFileIsOpenedManually = true
    mpvController.command(.loadfile, args: [path, "replace"])
    getPlaylist()
  }

  func playFileInPlaylist(_ pos: Int) {
    mpvController.setInt(MPVProperty.playlistPos, pos)
    getPlaylist()
  }

  func navigateInPlaylist(nextOrPrev: Bool) {
    mpvController.command(nextOrPrev ? .playlistNext : .playlistPrev, checkError: false)
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
    // check hwdec
    let askHwdec: (() -> Bool) = {
      let panel = NSAlert()
      panel.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
      panel.informativeText = NSLocalizedString("alert.filter_hwdec.message", comment: "")
      panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.turn_off", comment: "Turn off hardware decoding"))
      panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.use_copy", comment: "Switch to Auto(Copy)"))
      panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.abort", comment: "Abort"))
      switch panel.runModal() {
      case NSAlertFirstButtonReturn:  // turn off
        self.mpvController.setString(MPVProperty.hwdec, "no")
        self.ud.set(Preference.HardwareDecoderOption.disabled.rawValue, forKey: Preference.Key.hardwareDecoder)
        return true
      case NSAlertSecondButtonReturn:
        self.mpvController.setString(MPVProperty.hwdec, "auto-copy")
        self.ud.set(Preference.HardwareDecoderOption.autoCopy.rawValue, forKey: Preference.Key.hardwareDecoder)
        return true
      default:
        return false
      }
    }
    let hwdec = mpvController.getString(MPVProperty.hwdec)
    if hwdec == "auto" {
      // if not on main thread, post the alert in main thread
      if Thread.isMainThread {
        if !askHwdec() { return false }
      } else {
        var result = false
        DispatchQueue.main.sync {
          result = askHwdec()
        }
        if !result { return false }
      }
    }
    // try apply filter
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
    info.currentURL = path.contains("://") ? URL(string: path) : URL(fileURLWithPath: path)
    // Auto load
    backgroundQueueTicket += 1
    let currentFileIsOpenedManually = info.currentFileIsOpenedManually
    let currentTicket = backgroundQueueTicket
    backgroundQueue.async {
      // add files in same folder
      if currentFileIsOpenedManually {
        self.autoLoadFilesInCurrentFolder(ticket: currentTicket)
      }
      // auto load matched subtitles
      if let matchedSubs = self.info.matchedSubs[path] {
        for sub in matchedSubs {
          guard currentTicket == self.backgroundQueueTicket else { return }
          self.loadExternalSubFile(sub)
        }
        // set sub to the first one
        guard currentTicket == self.backgroundQueueTicket, self.mpvController.mpv != nil else { return }
        self.setTrack(1, forType: .sub)
      }
    }

  }

  /** This function is called right after file loaded. Should load all meta info here. */
  func fileLoaded() {
    invalidateTimer()
    triedUsingExactSeekForCurrentFile = false
    info.fileLoading = false
    info.haveDownloadedSub = false
    // Generate thumbnails if window has loaded video
    if mainWindow.isVideoLoaded {
      generateThumbnails()
    }
    DispatchQueue.main.sync {
      self.getTrackInfo()
      self.getSelectedTracks()
      self.getPlaylist()
      self.getChapters()
      syncPlayTimeTimer = Timer.scheduledTimer(timeInterval: TimeInterval(AppData.getTimeInterval),
                                               target: self, selector: #selector(self.syncUITime), userInfo: nil, repeats: true)
      mainWindow.updateTitle()
      if #available(OSX 10.12.2, *) {
        mainWindow.setupTouchBarUI()
      }
      // whether enter full screen
      if needEnterFullScreenForNextMedia {
        if ud.bool(forKey: Preference.Key.fullScreenWhenOpen) && !mainWindow.isInFullScreen {
          mainWindow.toggleWindowFullScreen()
        }
        // only enter fullscreen for first file
        needEnterFullScreenForNextMedia = false
      }
      // if need to switch to music mode
      if currentMediaIsAudio() {
        if !isInMiniPlayer { switchToMiniPlayer() }
      } else {
        if isInMiniPlayer {
          miniPlayer.close()
          switchBackFromMiniPlayer()
        }
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
    guard let dwidth = info.displayWidth, let dheight = info.displayHeight else {
      Utility.fatal("Cannot get video width and height")
    }
    if dwidth != 0 && dheight != 0 {
      DispatchQueue.main.sync {
        self.mainWindow.adjustFrameByVideoSize(dwidth, dheight)
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

  /**
   Add files in the same folder to playlist.
   It basically follows the following steps:
   - Get all files in current folder. Group and sort videos and audios, and add them to playlist.
   - Scan subtitles from search paths, combined with subs got in previous step.
   - Try match videos and subs by series and filename.
   - For unmatched videos and subs, perform fuzzy (but slow, O(n^2)) match for them.

   **Remark**: 
   
   This method is expected to be executed in `backgroundQueue` (see `backgroundQueueTicket`).
   Therefore accesses to `self.info` and mpv playlist must be guarded.
   */
  private func autoLoadFilesInCurrentFolder(ticket: Int) {
    AutoFileMatcher(player: self, ticket: ticket).startMatching()
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
    guard mainWindow.isWindowLoaded else { return }

    switch option {

    case .time:
      let time = mpvController.getDouble(MPVProperty.timePos)
      info.videoPosition = VideoTime(time)
      DispatchQueue.main.async {
        if self.isInMiniPlayer {
          self.miniPlayer.updatePlayTime(withDuration: false, andProgressBar: true)
        } else {
          self.mainWindow.updatePlayTime(withDuration: false, andProgressBar: true)
        }
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
        self.mainWindow.updatePlayTime(withDuration: true, andProgressBar: true)
        self.mainWindow.updateNetworkState()
      }

    case .playButton:
      let pause = mpvController.getFlag(MPVOption.PlaybackControl.pause)
      info.isPaused = pause
      DispatchQueue.main.async {
        self.mainWindow.updatePlayButtonState(pause ? NSOffState : NSOnState)
        self.miniPlayer.updatePlayButtonState(pause ? NSOffState : NSOnState)
        if #available(OSX 10.12.2, *) {
          self.mainWindow.updateTouchBarPlayBtn()
        }
      }

    case .volume:
      DispatchQueue.main.async {
        self.mainWindow.updateVolume()
        self.miniPlayer.updateVolume()
      }

    case .muteButton:
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

    case .playlist:
      DispatchQueue.main.async {
        if self.mainWindow.sideBarStatus == .playlist || self.isInMiniPlayer {
          self.mainWindow.playlistView.playlistTableView.reloadData()
        }
      }
    }
  }

  func sendOSD(_ osd: OSDMessage) {
    // querying `mainWindow.isWindowLoaded` will initialize mainWindow unexpectly
    guard mainWindow.isWindowLoaded else { return }
    if info.disableOSDForFileLoading {
      guard case .fileStart = osd else {
        return
      }
    }
    DispatchQueue.main.async {
      self.mainWindow.displayOSD(osd)
    }
  }

  func errorOpeningFileAndCloseMainWindow() {
    DispatchQueue.main.async {
      Utility.showAlert("error_open")
      self.mainWindow.close()
    }
  }

  func closeMainWindow() {
    DispatchQueue.main.async {
      self.mainWindow.close()
    }
  }

  func generateThumbnails() {
    guard let path = info.currentURL?.path else { return }
    info.thumbnails.removeAll(keepingCapacity: true)
    info.thumbnailsProgress = 0
    info.thumbnailsReady = false
    if UserDefaults.standard.bool(forKey: Preference.Key.enableThumbnailPreview) {
      if let cacheName = info.mpvMd5, ThumbnailCache.fileExists(forName: cacheName) {
        thumbnailQueue.async {
          if let thumbnails = ThumbnailCache.read(forName: cacheName) {
            self.info.thumbnails = thumbnails
            self.info.thumbnailsReady = true
            self.info.thumbnailsProgress = 1
            DispatchQueue.main.async {
              self.mainWindow?.touchBarPlaySlider?.needsDisplay = true
            }
          }
        }
      } else {
        ffmpegController.generateThumbnail(forFile: path)
      }
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
      track.isAlbumart = mpvController.getString(MPVProperty.trackListNAlbumart(index)) == "yes"
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

  func getPlaylist() {
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

  func currentMediaIsAudio() -> Bool {
    guard !info.isNetworkResource else { return false }
    let noVideoTrack = info.videoTracks.isEmpty
    let theOnlyVideoTrackIsAlbumCover = info.videoTracks.count == 1 && info.videoTracks.first!.isAlbumart
    return noVideoTrack || theOnlyVideoTrackIsAlbumCover
  }

  static func checkStatusForSleep() {
    for player in playerCores.filter({ !$0.info.isIdle }) {
      if !player.info.isPaused {
        SleepPreventer.preventSleep()
        return
      }
    }
    SleepPreventer.allowSleep()
  }

}


extension PlayerCore: FFmpegControllerDelegate {

  func didUpdatedThumbnails(_ thumbnails: [FFThumbnail]?, withProgress progress: Int) {
    if let thumbnails = thumbnails {
      info.thumbnails.append(contentsOf: thumbnails)
    }
    info.thumbnailsProgress = Double(progress) / Double(ffmpegController.thumbnailCount)
    DispatchQueue.main.async {
      self.mainWindow?.touchBarPlaySlider?.needsDisplay = true
    }
  }

  func didGeneratedThumbnails(_ thumbnails: [FFThumbnail], succeeded: Bool) {
    if succeeded {
      info.thumbnails = thumbnails
      info.thumbnailsReady = true
      info.thumbnailsProgress = 1
      DispatchQueue.main.async {
        self.mainWindow?.touchBarPlaySlider?.needsDisplay = true
      }
      if let cacheName = info.mpvMd5 {
        backgroundQueue.async {
          ThumbnailCache.write(self.info.thumbnails, forName: cacheName)
        }
      }
    }
  }
}
