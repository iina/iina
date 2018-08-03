//
//  PlayerCore.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MediaPlayer

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
      return wc.player
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
    if Preference.bool(for: .alwaysOpenInNewWindow) {
      return newPlayerCore
    } else {
      return active
    }
  }

  static var playerCores: [PlayerCore] = []
  static private var playerCoreCounter = 0

  static private func findIdlePlayerCore() -> PlayerCore? {
    return playerCores.first { $0.info.isIdle && !$0.info.fileLoading }
  }

  static private func createPlayerCore() -> PlayerCore {
    let pc = PlayerCore()
    pc.label = "\(playerCoreCounter)"
    playerCores.append(pc)
    pc.startMPV()
    playerCoreCounter += 1
    return pc
  }

  static func activeOrNewForMenuAction(isAlternative: Bool) -> PlayerCore {
    let useNew = Preference.bool(for: .alwaysOpenInNewWindow) != isAlternative
    return useNew ? newPlayerCore : active
  }

  // MARK: - Fields

  lazy var logger = Logger.getLogger("player\(label!)")

  var label: String!

  @available(macOS 10.12.2, *)
  var touchBarSupport: TouchBarSupport {
    get {
      return self._touchBarSupport as! TouchBarSupport
    }
  }
  private var _touchBarSupport: Any?

  /// A dispatch queue for auto load feature.
  let backgroundQueue = DispatchQueue(label: "IINAPlayerCoreTask", qos: .background)
  let playlistQueue = DispatchQueue(label: "IINAPlaylistTask", qos: .utility)
  let thumbnailQueue = DispatchQueue(label: "IINAPlayerCoreThumbnailTask", qos: .utility)

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

  var mpv: MPVController!

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
  var switchedToMiniPlayerManually = false
  var switchedBackFromMiniPlayerManually = false

  var isSearchingOnlineSubtitle = false

  // test seeking
  var triedUsingExactSeekForCurrentFile: Bool = false
  var useExactSeekForCurrentFile: Bool = true

  static var keyBindings: [String: KeyMapping] = [:]

  override init() {
    super.init()
    self.mpv = MPVController(playerCore: self)
    self.mainWindow = MainWindowController(playerCore: self)
    self.initialWindow = InitialWindowController(playerCore: self)
    self.miniPlayer = MiniPlayerWindowController(player: self)
    if #available(macOS 10.12.2, *) {
      self._touchBarSupport = TouchBarSupport(playerCore: self)
    }
  }

  // MARK: - Control

  func openURL(_ url: URL?, isNetworkResource: Bool = false, shouldAutoLoad: Bool = false) {
    guard let url = url else {
      logger?.error("empty file path or url")
      return
    }
    logger?.debug("Open URL: \(url.absoluteString)")
    let isNetwork = isNetworkResource && !url.isFileURL
    if shouldAutoLoad {
      info.shouldAutoLoadFiles = true
    }
    let path = isNetwork ? url.absoluteString : url.path
    openMainWindow(path: path, url: url, isNetwork: isNetwork)
  }

  func openURLString(_ str: String) {
    if str == "-" {
      openMainWindow(path: str, url: URL(string: "stdin")!, isNetwork: false)
    } else if str.first == "/" {
      let url = URL(fileURLWithPath: str)
      openMainWindow(path: str, url: url, isNetwork: false)
    } else {
      guard let pstr = str.addingPercentEncoding(withAllowedCharacters: .urlAllowed), let url = URL(string: pstr) else {
        logger?.error("Cannot add percent encoding for \(str)")
        return
      }
      openMainWindow(path: str, url: url, isNetwork: true)
    }
  }

  private func openMainWindow(path: String, url: URL, isNetwork: Bool) {
    logger?.debug("Opening \(path) in main window")
    info.currentURL = url
    // clear currentFolder since playlist is cleared, so need to auto-load again in playerCore#fileStarted
    info.currentFolder = nil
    info.isNetworkResource = isNetwork
    let _ = mainWindow.window
    if !mainWindow.window!.isVisible {
      SleepPreventer.preventSleep()
    }
    initialWindow.close()
    if isInMiniPlayer {
      miniPlayer.showWindow(nil)
    } else {
      mainWindow.showWindow(nil)
      mainWindow.windowDidOpen()
    }
    // Send load file command
    info.fileLoading = true
    info.justOpenedFile = true
    mpv.command(.loadfile, args: [path])
  }

  static func loadKeyBindings() {
    Logger.general?.debug("Loading key bindings")
    let userConfigs = Preference.dictionary(for: .inputConfigs)
    let iinaDefaultConfPath = PrefKeyBindingViewController.defaultConfigs["IINA Default"]!
    var inputConfPath = iinaDefaultConfPath
    if let confFromUd = Preference.string(for: .currentInputConfigName) {
      if let currentConfigFilePath = Utility.getFilePath(Configs: userConfigs, forConfig: confFromUd, showAlert: false) {
        inputConfPath = currentConfigFilePath
      }
    }
    setKeyBindings(KeyMapping.parseInputConf(at: inputConfPath) ?? KeyMapping.parseInputConf(at: iinaDefaultConfPath)!)
  }

  static func setKeyBindings(_ keyMappings: [KeyMapping]) {
    Logger.general?.debug("Set key bindings")
    var keyBindings: [String: KeyMapping] = [:]
    keyMappings.forEach { keyBindings[$0.key] = $0 }
    PlayerCore.keyBindings = keyBindings
    (NSApp.delegate as? AppDelegate)?.menuController.updateKeyEquivalentsFrom(keyMappings)
  }

  func startMPV() {
    // set path for youtube-dl
    let oldPath = String(cString: getenv("PATH")!)
    var path = Utility.exeDirURL.path + ":" + oldPath
    if let customYtdlPath = Preference.string(for: .ytdlSearchPath), !customYtdlPath.isEmpty {
      path = customYtdlPath + ":" + path
    }
    setenv("PATH", path, 1)
    logger?.debug("Set path to \(path)")

    // set http proxy
    if let proxy = Preference.string(for: .httpProxy), !proxy.isEmpty {
      setenv("http_proxy", "http://" + proxy, 1)
      logger?.debug("Set http_proxy to \(proxy)")
    }

    mpv.mpvInit()
  }

  func startMPVOpenGLCB(_ videoView: VideoView) {
    let mpvGLContext = mpv.mpvInitCB()
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
      mpv.mpvQuit()
    }
    isMpvTerminated = true
  }

  // invalidate timer
  func invalidateTimer() {
    self.syncPlayTimeTimer?.invalidate()
  }

  func switchToMiniPlayer(automatically: Bool = false) {
    logger?.debug("Switch to mini player, automatically=\(automatically)")
    if !automatically {
      switchedToMiniPlayerManually = true
    }
    switchedBackFromMiniPlayerManually = false
    miniPlayer.showWindow(self)
    miniPlayer.updateTrack()
    let playlistView = mainWindow.playlistView.view
    let videoView = mainWindow.videoView
    // reset down shift for playlistView
    mainWindow.playlistView.downShift = 0
    // hide sidebar
    if mainWindow.sideBarStatus != .hidden {
      mainWindow.hideSideBar(animate: false)
    }
    // move playist view
    playlistView.removeFromSuperview()
    mainWindow.playlistView.useCompactTabHeight = true
    miniPlayer.playlistWrapperView.addSubview(playlistView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": playlistView])
    // move video view
    videoView.removeFromSuperview()
    miniPlayer.videoWrapperView.addSubview(videoView, positioned: .below, relativeTo: nil)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": videoView])
    let (dw, dh) = videoSizeForDisplay
    miniPlayer.updateVideoViewAspectConstraint(withAspect: CGFloat(dw) / CGFloat(dh))
    // if no video track (or video info is still not available now), set aspect ratio for main window
    if let mw = mainWindow.window, mw.aspectRatio == .zero {
      let size = NSSize(width: dw, height: dh)
      mw.setFrame(NSRect(origin: mw.frame.origin, size: size), display: false)
      mw.aspectRatio = size
    }
    // if received video size before switching to music mode, hide default album art
    if !info.videoTracks.isEmpty {
      miniPlayer.defaultAlbumArt.isHidden = true
    }
    // in case of video size changed, reset mini player window size if playlist is folded
    if !miniPlayer.isPlaylistVisible {
      miniPlayer.setToInitialWindowSize(display: true, animate: false)
    }
    videoView.videoLayer.draw()
    // hide main window
    mainWindow.window?.orderOut(self)
    isInMiniPlayer = true
  }

  func switchBackFromMiniPlayer(automatically: Bool, showMainWindow: Bool = true) {
    logger?.debug("Switch to normal window from mini player, automatically=\(automatically)")
    if !automatically {
      switchedBackFromMiniPlayerManually = true
    }
    switchedToMiniPlayerManually = true
    mainWindow.playlistView.view.removeFromSuperview()
    mainWindow.playlistView.useCompactTabHeight = false
    // add back video view
    let mainWindowContentView = mainWindow.window!.contentView
    miniPlayer.videoViewAspectConstraint?.isActive = false
    miniPlayer.videoViewAspectConstraint = nil
    mainWindow.videoView.removeFromSuperview()
    mainWindowContentView?.addSubview(mainWindow.videoView, positioned: .below, relativeTo: nil)
    ([.top, .bottom, .left, .right] as [NSLayoutConstraint.Attribute]).forEach { attr in
      mainWindow.videoViewConstraints[attr] = NSLayoutConstraint(item: mainWindow.videoView, attribute: attr, relatedBy: .equal,
                                                                 toItem: mainWindowContentView, attribute: attr, multiplier: 1, constant: 0)
      mainWindow.videoViewConstraints[attr]!.isActive = true
    }
    // show main window
    if showMainWindow {
      mainWindow.window?.makeKeyAndOrderFront(self)
    }
    // if aspect ratio is not set
    if mainWindow.window?.aspectRatio == nil {
      mainWindow.window?.aspectRatio = NSSize(width: AppData.widthWhenNoVideo, height: AppData.heightWhenNoVideo)
    }
    isInMiniPlayer = false
    mainWindow.updateTitle()
  }

  // MARK: - MPV commands

  /** Pause / resume. Reset speed to 0 when pause. */
  func togglePause(_ set: Bool?) {
    if let setPause = set {
      // if paused by EOF, replay the video.
      if !setPause {
        if mpv.getFlag(MPVProperty.eofReached) {
          seek(absoluteSecond: 0)
        }
      }
      mpv.setFlag(MPVOption.PlaybackControl.pause, setPause)
    } else {
      if (info.isPaused) {
        if mpv.getFlag(MPVProperty.eofReached) {
          seek(absoluteSecond: 0)
        }
        mpv.setFlag(MPVOption.PlaybackControl.pause, false)
      } else {
        mpv.setFlag(MPVOption.PlaybackControl.pause, true)
      }
    }
  }

  func stop() {
    mpv.command(.stop)
    invalidateTimer()
  }

  func toogleMute(_ set: Bool? = nil) {
    let newState = set ?? !mpv.getFlag(MPVOption.Audio.mute)
    mpv.setFlag(MPVOption.Audio.mute, newState)
  }

  func seek(percent: Double, forceExact: Bool = false) {
    var percent = percent
    // mpv will play next file automatically when seek to EOF.
    // We clamp to a Range to ensure that we don't try to seek to 100%.
    // however, it still won't work for videos with large keyframe interval.
    if let duration = info.videoDuration?.second,
      duration > 0 {
      percent = percent.clamped(to: 0..<100)
    }
    let useExact = forceExact ? true : Preference.bool(for: .useExactSeek)
    let seekMode = useExact ? "absolute-percent+exact" : "absolute-percent"
    mpv.command(.seek, args: ["\(percent)", seekMode], checkError: false)
  }

  func seek(relativeSecond: Double, option: Preference.SeekOption) {
    switch option {

    case .relative:
      mpv.command(.seek, args: ["\(relativeSecond)", "relative"], checkError: false)

    case .exact:
      mpv.command(.seek, args: ["\(relativeSecond)", "relative+exact"], checkError: false)

    case .auto:
      // for each file , try use exact and record interval first
      if !triedUsingExactSeekForCurrentFile {
        mpv.recordedSeekTimeListener = { [unowned self] interval in
          // if seek time < 0.05, then can use exact
          self.useExactSeekForCurrentFile = interval < 0.05
        }
        mpv.needRecordSeekTime = true
        triedUsingExactSeekForCurrentFile = true
      }
      let seekMode = useExactSeekForCurrentFile ? "relative+exact" : "relative"
      mpv.command(.seek, args: ["\(relativeSecond)", seekMode], checkError: false)

    }
  }

  func seek(absoluteSecond: Double) {
    mpv.command(.seek, args: ["\(absoluteSecond)", "absolute+exact"])
  }

  func frameStep(backwards: Bool) {
    if backwards {
      mpv.command(.frameBackStep)
    } else {
      mpv.command(.frameStep)
    }
  }

  func screenshot() {
    let option = Preference.bool(for: .screenshotIncludeSubtitle) ? "subtitles" : "video"
    mpv.command(.screenshot, args: [option])
    sendOSD(.screenshot)
  }

  func abLoop() {
    // may subject to change
    mpv.command(.abLoop)
    let a = mpv.getDouble(MPVOption.PlaybackControl.abLoopA)
    let b = mpv.getDouble(MPVOption.PlaybackControl.abLoopB)
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
    let isLoop = mpv.getFlag(MPVOption.PlaybackControl.loopFile)
    mpv.setFlag(MPVOption.PlaybackControl.loopFile, !isLoop)
  }

  func togglePlaylistLoop() {
    let loopStatus = mpv.getString(MPVOption.PlaybackControl.loopPlaylist)
    let isLoop = (loopStatus == "inf" || loopStatus == "force")
    mpv.setString(MPVOption.PlaybackControl.loopPlaylist, isLoop ? "no" : "inf")
  }

  func toggleShuffle() {
    mpv.command(.playlistShuffle)
    postNotification(.iinaPlaylistChanged)
  }

  func setVolume(_ volume: Double, constrain: Bool = true) {
    let maxVolume = Preference.integer(for: .maxVolume)
    let constrainedVolume = volume.clamped(to: 0...Double(maxVolume))
    let appliedVolume = constrain ? constrainedVolume : volume
    info.volume = appliedVolume
    mpv.setDouble(MPVOption.Audio.volume, appliedVolume)
    Preference.set(constrainedVolume, for: .softVolume)
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
    mpv.setInt(name, index)
    getSelectedTracks()
  }

  /** Set speed. */
  func setSpeed(_ speed: Double) {
    mpv.setDouble(MPVOption.PlaybackControl.speed, speed)
  }

  func setVideoAspect(_ aspect: String) {
    if Regex.aspect.matches(aspect) {
      mpv.setString(MPVProperty.videoAspect, aspect)
      info.unsureAspect = aspect
    } else {
      mpv.setString(MPVProperty.videoAspect, "-1")
      // if not a aspect string, set aspect to default, and also the info string.
      info.unsureAspect = "Default"
    }
  }

  func setVideoRotate(_ degree: Int) {
    if AppData.rotations.index(of: degree)! >= 0 {
      mpv.setInt(MPVOption.Video.videoRotate, degree)
      info.rotation = degree
    }
  }

  func setFlip(_ enable: Bool) {
    if enable {
      if info.flipFilter == nil {
        let vf = MPVFilter.flip()
        vf.label = Constants.FilterName.flip
        if addVideoFilter(vf) {
          info.flipFilter = vf
        }
      }
    } else {
      if let vf = info.flipFilter {
        let _ = removeVideoFilter(vf)
        info.flipFilter = nil
      }
    }
  }

  func setMirror(_ enable: Bool) {
    if enable {
      if info.mirrorFilter == nil {
        let vf = MPVFilter.mirror()
        vf.label = Constants.FilterName.mirror
        if addVideoFilter(vf) {
          info.mirrorFilter = vf
        }
      }
    } else {
      if let vf = info.mirrorFilter {
        let _ = removeVideoFilter(vf)
        info.mirrorFilter = nil
      }
    }
  }

  func toggleDeinterlace(_ enable: Bool) {
    mpv.setFlag(MPVOption.Video.deinterlace, enable)
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
    mpv.command(.set, args: [optionName, value.description])
  }

  func loadExternalAudioFile(_ url: URL) {
    mpv.command(.audioAdd, args: [url.path], checkError: false) { code in
      if code < 0 {
        self.logger?.error("Unsupported audio: \(url.path)")
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_audio")
        }
      }
    }
  }

  func loadExternalSubFile(_ url: URL, delay: Bool = false) {
    if let track = info.subTracks.first(where: { $0.externalFilename == url.path }) {
      mpv.command(.subReload, args: [String(track.id)], checkError: false)
      return
    }

    mpv.command(.subAdd, args: [url.path], checkError: false) { code in
      if code < 0 {
        self.logger?.error("Unsupported sub: \(url.path)")
        // if another modal panel is shown, popping up an alert now will cause some infinite loop.
        if delay {
          DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) {
            Utility.showAlert("unsupported_sub")
          }
        } else {
          DispatchQueue.main.async {
            Utility.showAlert("unsupported_sub")
          }
        }
      }
    }
  }

  func reloadAllSubs() {
    let currentSubName = info.currentTrack(.sub)?.externalFilename
    for subTrack in info.subTracks {
      mpv.command(.subReload, args: ["\(subTrack.id)"], checkError: false) { code in
        if code < 0 {
          self.logger?.error("Failed reloading subtitles: error code \(code)")
        }
      }
    }
    getTrackInfo()
    if let currentSub = info.subTracks.first(where: {$0.externalFilename == currentSubName}) {
      setTrack(currentSub.id, forType: .sub)
    }
    mainWindow?.quickSettingView.reload()
  }

  func setAudioDelay(_ delay: Double) {
    mpv.setDouble(MPVOption.Audio.audioDelay, delay)
  }

  func setSubDelay(_ delay: Double) {
    mpv.setDouble(MPVOption.Subtitles.subDelay, delay)
  }

  func addToPlaylist(_ path: String) {
    mpv.command(.loadfile, args: [path, "append"])
  }

  func playlistMove(_ from: Int, to: Int) {
    mpv.command(.playlistMove, args: ["\(from)", "\(to)"])
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
    mpv.command(.playlistRemove, args: [index.description])
  }

  func clearPlaylist() {
    mpv.command(.playlistClear)
  }

  func removeFromPlaylist(index: Int) {
    mpv.command(.playlistRemove, args: ["\(index)"])
  }

  func playFile(_ path: String) {
    info.justOpenedFile = true
    info.shouldAutoLoadFiles = true
    mpv.command(.loadfile, args: [path, "replace"])
    getPlaylist()
  }

  func playFileInPlaylist(_ pos: Int) {
    mpv.setInt(MPVProperty.playlistPos, pos)
    getPlaylist()
  }

  func navigateInPlaylist(nextMedia: Bool) {
    mpv.command(nextMedia ? .playlistNext : .playlistPrev, checkError: false)
  }

  func playChapter(_ pos: Int) {
    let chapter = info.chapters[pos]
    mpv.command(.seek, args: ["\(chapter.time.second)", "absolute"])
    // need to update time pos
    syncUITime()
  }

  func setCrop(fromString str: String) {
    let vwidth = info.videoWidth!
    let vheight = info.videoHeight!
    if let aspect = Aspect(string: str) {
      let cropped = NSMakeSize(CGFloat(vwidth), CGFloat(vheight)).crop(withAspect: aspect)
      let vf = MPVFilter.crop(w: Int(cropped.width), h: Int(cropped.height), x: nil, y: nil)
      vf.label = Constants.FilterName.crop
      setCrop(fromFilter: vf)
      // warning! may should not update it here
      info.unsureCrop = str
      info.cropFilter = vf
    } else {
      if let filter = info.cropFilter {
        let _ = removeVideoFilter(filter)
        info.unsureCrop = "None"
      }
    }
  }

  func setCrop(fromFilter filter: MPVFilter) {
    filter.label = Constants.FilterName.crop
    if addVideoFilter(filter) {
      info.cropFilter = filter
    }
  }

  func setAudioEq(fromFilter filter: MPVFilter) {
    filter.label = Constants.FilterName.audioEq
    _ = addAudioFilter(filter)
    info.audioEqFilter = filter
  }

  func removeAudioEqFilter() {
    if let prevFilter = info.audioEqFilter {
      _ = removeAudioFilter(prevFilter)
      info.audioEqFilter = nil
    }
  }

  func addVideoFilter(_ filter: MPVFilter) -> Bool {
    logger?.debug("Adding video filter \(filter.stringFormat)...")
    // check hwdec
    let askHwdec: (() -> Bool) = {
      let panel = NSAlert()
      panel.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
      panel.informativeText = NSLocalizedString("alert.filter_hwdec.message", comment: "")
      panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.turn_off", comment: "Turn off hardware decoding"))
      panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.use_copy", comment: "Switch to Auto(Copy)"))
      panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.abort", comment: "Abort"))
      switch panel.runModal() {
      case .alertFirstButtonReturn:  // turn off
        self.mpv.setString(MPVProperty.hwdec, "no")
        Preference.set(Preference.HardwareDecoderOption.disabled.rawValue, for: .hardwareDecoder)
        return true
      case .alertSecondButtonReturn:
        self.mpv.setString(MPVProperty.hwdec, "auto-copy")
        Preference.set(Preference.HardwareDecoderOption.autoCopy.rawValue, for: .hardwareDecoder)
        return true
      default:
        return false
      }
    }
    let hwdec = mpv.getString(MPVProperty.hwdec)
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
    mpv.command(.vf, args: ["add", filter.stringFormat], checkError: false) { result = $0 >= 0 }
    logger?.debug(result ? "Succeeded" : "Failed")
    return result
  }

  func removeVideoFilter(_ filter: MPVFilter) -> Bool {
    var result = true
    if let label = filter.label {
      mpv.command(.vf, args: ["del", "@" + label], checkError: false) { result = $0 >= 0 }
    } else {
      mpv.command(.vf, args: ["del", filter.stringFormat], checkError: false) { result = $0 >= 0 }
    }
    return result
  }

  func addAudioFilter(_ filter: MPVFilter) -> Bool {
    var result = true
    mpv.command(.af, args: ["add", filter.stringFormat], checkError: false) { result = $0 >= 0 }
    return result
  }

  func removeAudioFilter(_ filter: MPVFilter) -> Bool {
    var result = true
    mpv.command(.af, args: ["del", filter.stringFormat], checkError: false)  { result = $0 >= 0 }
    return result
  }

  func getAudioDevices() -> [[String: String]] {
    let raw = mpv.getNode(MPVProperty.audioDeviceList)
    if let list = raw as? [[String: String]] {
      return list
    } else {
      return []
    }
  }

  func setAudioDevice(_ name: String) {
    mpv.setString(MPVProperty.audioDevice, name)
  }

  /** Scale is a double value in [-100, -1] + [1, 100] */
  func setSubScale(_ scale: Double) {
    if scale > 0 {
      mpv.setDouble(MPVOption.Subtitles.subScale, scale)
    } else {
      mpv.setDouble(MPVOption.Subtitles.subScale, -scale)
    }
  }

  func setSubPos(_ pos: Int) {
    mpv.setInt(MPVOption.Subtitles.subPos, pos)
  }

  func setSubTextColor(_ colorString: String) {
    mpv.setString("options/" + MPVOption.Subtitles.subColor, colorString)
  }

  func setSubTextSize(_ size: Double) {
    mpv.setDouble("options/" + MPVOption.Subtitles.subFontSize, size)
  }

  func setSubTextBold(_ bold: Bool) {
    mpv.setFlag("options/" + MPVOption.Subtitles.subBold, bold)
  }

  func setSubTextBorderColor(_ colorString: String) {
    mpv.setString("options/" + MPVOption.Subtitles.subBorderColor, colorString)
  }

  func setSubTextBorderSize(_ size: Double) {
    mpv.setDouble("options/" + MPVOption.Subtitles.subBorderSize, size)
  }

  func setSubTextBgColor(_ colorString: String) {
    mpv.setString("options/" + MPVOption.Subtitles.subBackColor, colorString)
  }

  func setSubEncoding(_ encoding: String) {
    mpv.setString(MPVOption.Subtitles.subCodepage, encoding)
    info.subEncoding = encoding
  }

  func setSubFont(_ font: String) {
    mpv.setString(MPVOption.Subtitles.subFont, font)
  }

  func execKeyCode(_ code: String) {
    mpv.command(.keypress, args: [code], checkError: false) { errCode in
      if errCode < 0 {
        self.logger?.error("Error when executing key code (\(errCode))")
      }
    }
  }

  func savePlaybackPosition() {
    logger?.debug("Write watch later config")
    mpv.command(.writeWatchLaterConfig)
    if let url = info.currentURL {
      Preference.set(url, for: .iinaLastPlayedFilePath)
      // Write to cache directly (rather than calling `refreshCachedVideoProgress`).
      // If user only closed the window but didn't quit the app, this can make sure playlist displays the correct progress.
      info.cachedVideoDurationAndProgress[url.path] = (duration: info.videoDuration?.second, progress: info.videoPosition?.second)
    }
    if let position = info.videoPosition?.second {
      Preference.set(position, for: .iinaLastPlayedFilePosition)
    }
  }

  func getGeometry() -> GeometryDef? {
    let geometry = mpv.getString(MPVOption.Window.geometry) ?? ""
    return GeometryDef.parse(geometry)
  }


  // MARK: - Listeners

  func fileStarted() {
    logger?.debug("File started")
    info.justStartedFile = true
    info.disableOSDForFileLoading = true
    currentMediaIsAudio = .unknown
    guard let path = mpv.getString(MPVProperty.path) else { return }
    info.currentURL = path.contains("://") ? URL(string: path) : URL(fileURLWithPath: path)
    info.isNetworkResource = !info.currentURL!.isFileURL
    // Auto load
    backgroundQueueTicket += 1
    let shouldAutoLoadFiles = info.shouldAutoLoadFiles
    let currentTicket = backgroundQueueTicket
    backgroundQueue.async {
      // add files in same folder
      if shouldAutoLoadFiles {
        self.logger?.debug("Started auto load")
        self.autoLoadFilesInCurrentFolder(ticket: currentTicket)
      }
      // auto load matched subtitles
      if let matchedSubs = self.info.matchedSubs[path] {
        self.logger?.debug("Found \(matchedSubs.count) subs for current file")
        for sub in matchedSubs {
          guard currentTicket == self.backgroundQueueTicket else { return }
          self.loadExternalSubFile(sub)
        }
        // set sub to the first one
        guard currentTicket == self.backgroundQueueTicket, self.mpv.mpv != nil else { return }
        self.setTrack(1, forType: .sub)
      }
      self.autoSearchOnlineSub()
    }
  }

  /** This function is called right after file loaded. Should load all meta info here. */
  func fileLoaded() {
    logger?.debug("File loaded")
    invalidateTimer()
    triedUsingExactSeekForCurrentFile = false
    info.fileLoading = false
    info.haveDownloadedSub = false
    // generate thumbnails if window has loaded video
    if mainWindow.isVideoLoaded {
      generateThumbnails()
    }
    // main thread stuff
    getTrackInfo()
    getSelectedTracks()
    getPlaylist()
    getChapters()
    DispatchQueue.main.sync {
      syncPlayTimeTimer = Timer.scheduledTimer(timeInterval: TimeInterval(AppData.getTimeInterval),
                                               target: self, selector: #selector(self.syncUITime), userInfo: nil, repeats: true)
      if #available(macOS 10.12.2, *) {
        touchBarSupport.setupTouchBarUI()
      }

      if info.aid == 0 {
        mainWindow.muteButton.isEnabled = false
        mainWindow.volumeSlider.isEnabled = false
      }
    }
    // set initial properties for the first file
    if info.justLaunched {
      if Preference.bool(for: .fullScreenWhenOpen) && !mainWindow.isInFullScreen && !isInMiniPlayer {
        DispatchQueue.main.async {
          self.mainWindow.toggleWindowFullScreen()
        }
      }
      info.justLaunched = false
    }
    // add to history
    if let url = info.currentURL {
      let duration = info.videoDuration ?? .zero
      HistoryController.shared.add(url, duration: duration.second)
      if Preference.bool(for: .recordRecentFiles) && Preference.bool(for: .trackAllFilesInRecentOpenMenu) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
      }
    }
    postNotification(.iinaFileLoaded)
  }

  func playbackRestarted() {
    logger?.debug("Playback restarted")
    reloadSavedIINAfilters()
    DispatchQueue.main.async {
      Timer.scheduledTimer(timeInterval: TimeInterval(0.2), target: self, selector: #selector(self.reEnableOSDAfterFileLoading), userInfo: nil, repeats: false)
    }
  }

  func trackListChanged() {
    logger?.debug("Track list changed")
    getTrackInfo()
    getSelectedTracks()
    let audioStatusWasUnkownBefore = currentMediaIsAudio == .unknown
    currentMediaIsAudio = checkCurrentMediaIsAudio()
    let audioStatusIsAvailableNow = currentMediaIsAudio != .unknown && audioStatusWasUnkownBefore
    // if need to switch to music mode
    if audioStatusIsAvailableNow && Preference.bool(for: .autoSwitchToMusicMode) {
      if currentMediaIsAudio == .isAudio {
        if !isInMiniPlayer && !mainWindow.isInFullScreen && !switchedBackFromMiniPlayerManually {
          logger?.debug("Current media is audio, switch to mini player")
          DispatchQueue.main.sync {
            switchToMiniPlayer(automatically: false)
          }
        }
      } else {
        if isInMiniPlayer && !switchedToMiniPlayerManually {
          logger?.debug("Current media is not audio, switch to normal window")
          DispatchQueue.main.sync {
            miniPlayer.close()
            switchBackFromMiniPlayer(automatically: true)
          }
        }
      }
    }
  }

  @objc
  private func reEnableOSDAfterFileLoading() {
    info.disableOSDForFileLoading = false
  }

  private func autoSearchOnlineSub() {
    Thread.sleep(forTimeInterval: 0.5)
    if Preference.bool(for: .autoSearchOnlineSub) && info.subTracks.isEmpty &&
      info.videoDuration!.second >= Preference.double(for: .autoSearchThreshold) * 60 {
      mainWindow.menuActionHandler.menuFindOnlineSub(.dummy)
    }
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

  func notifyMainWindowVideoSizeChanged() {
    DispatchQueue.main.sync {
      self.mainWindow.adjustFrameByVideoSize()
      if self.isInMiniPlayer {
        self.miniPlayer.updateVideoSize()
      }
    }
  }

  // difficult to use option set
  enum SyncUIOption {
    case time
    case timeAndCache
    case playButton
    case volume
    case muteButton
    case chapterList
    case playlist
    case additionalInfo
  }

  @objc func syncUITime() {
    if #available(macOS 10.13, *) {
      if RemoteCommandController.useSystemMediaControl {
        NowPlayingInfoManager.updateInfo()
      }
    }
    if info.isNetworkResource {
      syncUI(.timeAndCache)
    } else {
      syncUI(.time)
    }
    if !isInMiniPlayer &&
      mainWindow.isInFullScreen && mainWindow.displayTimeAndBatteryInFullScreen &&
      !mainWindow.additionalInfoView.isHidden {
      syncUI(.additionalInfo)
    }
  }

  func syncUI(_ option: SyncUIOption) {
    // if window not loaded, ignore
    guard mainWindow.isWindowLoaded else { return }
    logger?.verbose("Syncing UI \(option)")

    switch option {

    case .time:
      let time = mpv.getDouble(MPVProperty.timePos)
      info.videoPosition?.second = time
      info.constrainVideoPosition()
      DispatchQueue.main.async {
        if self.isInMiniPlayer {
          self.miniPlayer.updatePlayTime(withDuration: false, andProgressBar: true)
        } else {
          self.mainWindow.updatePlayTime(withDuration: false, andProgressBar: true)
        }
      }

    case .timeAndCache:
      let time = mpv.getDouble(MPVProperty.timePos)
      info.videoPosition?.second = time
      info.constrainVideoPosition()
      info.pausedForCache = mpv.getFlag(MPVProperty.pausedForCache)
      info.cacheSize = mpv.getInt(MPVProperty.cacheSize)
      info.cacheUsed = mpv.getInt(MPVProperty.cacheUsed)
      info.cacheSpeed = mpv.getInt(MPVProperty.cacheSpeed)
      info.cacheTime = mpv.getInt(MPVProperty.demuxerCacheTime)
      info.bufferingState = mpv.getInt(MPVProperty.cacheBufferingState)
      DispatchQueue.main.async {
        self.mainWindow.updatePlayTime(withDuration: true, andProgressBar: true)
        self.mainWindow.updateNetworkState()
      }

    case .playButton:
      let pause = mpv.getFlag(MPVOption.PlaybackControl.pause)
      info.isPaused = pause
      DispatchQueue.main.async {
        self.mainWindow.updatePlayButtonState(pause ? .off : .on)
        self.miniPlayer.updatePlayButtonState(pause ? .off : .on)
        if #available(macOS 10.12.2, *) {
          self.touchBarSupport.updateTouchBarPlayBtn()
        }
      }

    case .volume, .muteButton:
      DispatchQueue.main.async {
        self.mainWindow.updateVolume()
        self.miniPlayer.updateVolume()
      }

    case .chapterList:
      DispatchQueue.main.async {
        // this should avoid sending reload when table view is not ready
        if self.isInMiniPlayer ? self.miniPlayer.isPlaylistVisible : self.mainWindow.sideBarStatus == .playlist {
          self.mainWindow.playlistView.chapterTableView.reloadData()
        }
      }

    case .playlist:
      DispatchQueue.main.async {
        if self.isInMiniPlayer ? self.miniPlayer.isPlaylistVisible : self.mainWindow.sideBarStatus == .playlist {
          self.mainWindow.playlistView.playlistTableView.reloadData()
        }
      }

    case .additionalInfo:
      DispatchQueue.main.async {
        let timeString = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        if let capacity = PowerSource.getList().filter({ $0.type == "InternalBattery" }).first?.currentCapacity {
          self.mainWindow.additionalInfoLabel.stringValue = "\(timeString) | \(capacity)%"
        } else {
          self.mainWindow.additionalInfoLabel.stringValue = "\(timeString)"
        }
      }
    }
  }

  func sendOSD(_ osd: OSDMessage, autoHide: Bool = true, accessoryView: NSView? = nil) {
    // querying `mainWindow.isWindowLoaded` will initialize mainWindow unexpectly
    guard mainWindow.isWindowLoaded && Preference.bool(for: .enableOSD) else { return }
    if info.disableOSDForFileLoading {
      guard case .fileStart = osd else {
        return
      }
    }
    DispatchQueue.main.async {
      self.mainWindow.displayOSD(osd, autoHide: autoHide, accessoryView: accessoryView)
    }
  }

  func hideOSD() {
    DispatchQueue.main.async {
      self.mainWindow.hideOSD()
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
    logger?.debug("Getting thumbnails")
    if #available(macOS 10.12.2, *) {
      DispatchQueue.main.async {
        self.touchBarSupport.touchBarPlaySlider?.resetCachedThumbnails()
      }
    }
    guard !info.isNetworkResource,
      let path = info.currentURL?.path else { return }
    info.thumbnails.removeAll(keepingCapacity: true)
    info.thumbnailsProgress = 0
    info.thumbnailsReady = false
    if Preference.bool(for: .enableThumbnailPreview) {
      if let cacheName = info.mpvMd5, ThumbnailCache.fileIsCached(forName: cacheName, forVideo: info.currentURL) {
        logger?.debug("Found thumbnail cache")
        thumbnailQueue.async {
          if let thumbnails = ThumbnailCache.read(forName: cacheName) {
            self.info.thumbnails = thumbnails
            self.info.thumbnailsReady = true
            self.info.thumbnailsProgress = 1
            self.refreshTouchBarSlider()
          } else {
            self.logger?.error("Cannot read thumbnail from cache")
          }
        }
      } else {
        logger?.debug("Request new thumbnails")
        ffmpegController.generateThumbnail(forFile: path)
      }
    }
  }

  func refreshTouchBarSlider() {
    if #available(macOS 10.12.2, *) {
      DispatchQueue.main.async {
        self.touchBarSupport.touchBarPlaySlider?.needsDisplay = true
      }
    }
  }

  // MARK: - Getting info

  func getTrackInfo() {
    info.audioTracks.removeAll(keepingCapacity: true)
    info.videoTracks.removeAll(keepingCapacity: true)
    info.subTracks.removeAll(keepingCapacity: true)
    let trackCount = mpv.getInt(MPVProperty.trackListCount)
    for index in 0..<trackCount {
      // get info for each track
      guard let trackType = mpv.getString(MPVProperty.trackListNType(index)) else { continue }
      let track = MPVTrack(id: mpv.getInt(MPVProperty.trackListNId(index)),
                           type: MPVTrack.TrackType(rawValue: trackType)!,
                           isDefault: mpv.getFlag(MPVProperty.trackListNDefault(index)),
                           isForced: mpv.getFlag(MPVProperty.trackListNForced(index)),
                           isSelected: mpv.getFlag(MPVProperty.trackListNSelected(index)),
                           isExternal: mpv.getFlag(MPVProperty.trackListNExternal(index)))
      track.srcId = mpv.getInt(MPVProperty.trackListNSrcId(index))
      track.title = mpv.getString(MPVProperty.trackListNTitle(index))
      track.lang = mpv.getString(MPVProperty.trackListNLang(index))
      track.codec = mpv.getString(MPVProperty.trackListNCodec(index))
      track.externalFilename = mpv.getString(MPVProperty.trackListNExternalFilename(index))
      track.isAlbumart = mpv.getString(MPVProperty.trackListNAlbumart(index)) == "yes"
      track.decoderDesc = mpv.getString(MPVProperty.trackListNDecoderDesc(index))
      track.demuxW = mpv.getInt(MPVProperty.trackListNDemuxW(index))
      track.demuxH = mpv.getInt(MPVProperty.trackListNDemuxH(index))
      track.demuxFps = mpv.getDouble(MPVProperty.trackListNDemuxFps(index))
      track.demuxChannelCount = mpv.getInt(MPVProperty.trackListNDemuxChannelCount(index))
      track.demuxChannels = mpv.getString(MPVProperty.trackListNDemuxChannels(index))
      track.demuxSamplerate = mpv.getInt(MPVProperty.trackListNDemuxSamplerate(index))

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
    info.aid = mpv.getInt(MPVOption.TrackSelection.aid)
    info.vid = mpv.getInt(MPVOption.TrackSelection.vid)
    info.sid = mpv.getInt(MPVOption.TrackSelection.sid)
    info.secondSid = mpv.getInt(MPVOption.Subtitles.secondarySid)
  }

  func getPlaylist() {
    info.playlist.removeAll()
    let playlistCount = mpv.getInt(MPVProperty.playlistCount)
    for index in 0..<playlistCount {
      let playlistItem = MPVPlaylistItem(filename: mpv.getString(MPVProperty.playlistNFilename(index))!,
                                         isCurrent: mpv.getFlag(MPVProperty.playlistNCurrent(index)),
                                         isPlaying: mpv.getFlag(MPVProperty.playlistNPlaying(index)),
                                         title: mpv.getString(MPVProperty.playlistNTitle(index)))
      info.playlist.append(playlistItem)
    }
  }

  func getChapters() {
    info.chapters.removeAll()
    let chapterCount = mpv.getInt(MPVProperty.chapterListCount)
    if chapterCount == 0 {
      return
    }
    for index in 0..<chapterCount {
      let chapter = MPVChapter(title:     mpv.getString(MPVProperty.chapterListNTitle(index)),
                               startTime: mpv.getDouble(MPVProperty.chapterListNTime(index)),
                               index:     index)
      info.chapters.append(chapter)
    }
  }

  // MARK: - Notifications

  func postNotification(_ name: Notification.Name) {
    NotificationCenter.default.post(Notification(name: name, object: self))
  }

  // MARK: - Utils

  /**
   Non-nil and non-zero width/height value calculated for video window, from current `dwidth`
   and `dheight` while taking pure audio files and video rotations into consideration.
   */
  var videoSizeForDisplay: (Int, Int) {
    get {
      var width: Int
      var height: Int

      if let w = info.displayWidth, let h = info.displayHeight {
        // when width and height == 0 there's no video track
        width = w == 0 ? AppData.widthWhenNoVideo : w
        height = h == 0 ? AppData.heightWhenNoVideo : h
      } else {
        // we cannot get dwidth and dheight, which is unexpected. This block should never be executed
        // but just in case, let's log the error.
        logger?.warning("videoSizeForDisplay: Cannot get dwidth and dheight")
        width = AppData.widthWhenNoVideo
        height = AppData.heightWhenNoVideo
      }

      // if video has rotation
      let netRotate = mpv.getInt(MPVProperty.videoParamsRotate) - mpv.getInt(MPVOption.Video.videoRotate)
      let rotate = netRotate >= 0 ? netRotate : netRotate + 360
      if rotate == 90 || rotate == 270 {
        swap(&width, &height)
      }
      return (width, height)
    }
  }

  var originalVideoSize: (Int, Int) {
    get {
      if let w = info.videoWidth, let h = info.videoHeight {
        let netRotate = mpv.getInt(MPVProperty.videoParamsRotate) - mpv.getInt(MPVOption.Video.videoRotate)
        let rotate = netRotate >= 0 ? netRotate : netRotate + 360
        if rotate == 90 || rotate == 270 {
          return (h, w)
        } else {
          return (w, h)
        }
      } else {
        return (0, 0)
      }
    }
  }

  func getMediaTitle(withExtension: Bool = true) -> String {
    let mediaTitle = mpv.getString(MPVProperty.mediaTitle)
    let mediaPath = withExtension ? info.currentURL?.path : info.currentURL?.deletingPathExtension().path
    return mediaTitle ?? mediaPath ?? ""
  }

  func getMusicMetadata() -> (title: String, album: String, artist: String) {
    let title = mpv.getString(MPVProperty.mediaTitle) ?? ""
    let album = mpv.getString("metadata/by-key/album") ?? ""
    let artist = mpv.getString("metadata/by-key/artist") ?? ""
    return (title, album, artist)
  }

  /** Check if there are IINA filters saved in watch_later file. */
  func reloadSavedIINAfilters() {
    // vf
    let videoFilters = mpv.getFilters(MPVProperty.vf)
    for filter in videoFilters {
      guard let label = filter.label else { continue }
      switch label {
      case Constants.FilterName.crop:
        info.cropFilter = filter
        info.unsureCrop = ""
      case Constants.FilterName.flip:
        info.flipFilter = filter
      case Constants.FilterName.mirror:
        info.mirrorFilter = filter
      case Constants.FilterName.delogo:
        info.delogoFilter = filter
      default:
        break
      }
    }
    // af
    let audioFilters = mpv.getFilters(MPVProperty.af)
    for filter in audioFilters {
      guard let label = filter.label else { continue }
      switch label {
      case Constants.FilterName.audioEq:
        info.audioEqFilter = filter
      default:
        break
      }
    }
  }

  /**
   Get video duration and playback progress, then save it to info.
   It may take some time to run this method, so it should be used in background.
   */
  func refreshCachedVideoProgress(forVideoPath path: String) {
    let duration = FFmpegController.probeVideoDuration(forFile: path)
    let progress = Utility.playbackProgressFromWatchLater(path.md5)
    info.cachedVideoDurationAndProgress[path] = (
      duration: (duration > 0 ? duration : nil),
      progress: progress?.second
    )
  }

  enum CurrentMediaIsAudioStatus {
    case unknown
    case isAudio
    case notAudio
  }

  var currentMediaIsAudio = CurrentMediaIsAudioStatus.unknown

  func checkCurrentMediaIsAudio() -> CurrentMediaIsAudioStatus {
    guard !info.isNetworkResource else { return .notAudio }
    let noVideoTrack = info.videoTracks.isEmpty
    let noAudioTrack = info.audioTracks.isEmpty
    if noVideoTrack && noAudioTrack {
      return .unknown
    }
    let allVideoTracksAreAlbumCover = !info.videoTracks.contains { !$0.isAlbumart }
    return (noVideoTrack || allVideoTracksAreAlbumCover) ? .isAudio : .notAudio
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

  func didUpdate(_ thumbnails: [FFThumbnail]?, forFile filename: String, withProgress progress: Int) {
    guard let currentFilePath = info.currentURL?.path, currentFilePath == filename else { return }
    logger?.debug("Got new thumbnails, progress \(progress)")
    if let thumbnails = thumbnails {
      info.thumbnails.append(contentsOf: thumbnails)
    }
    info.thumbnailsProgress = Double(progress) / Double(ffmpegController.thumbnailCount)
    refreshTouchBarSlider()
  }

  func didGenerate(_ thumbnails: [FFThumbnail], forFile filename: String, succeeded: Bool) {
    guard let currentFilePath = info.currentURL?.path, currentFilePath == filename else { return }
    logger?.debug("Got all thumbnails, succeeded=\(succeeded)")
    if succeeded {
      info.thumbnails = thumbnails
      info.thumbnailsReady = true
      info.thumbnailsProgress = 1
      refreshTouchBarSlider()
      if let cacheName = info.mpvMd5 {
        backgroundQueue.async {
          ThumbnailCache.write(self.info.thumbnails, forName: cacheName, forVideo: self.info.currentURL)
        }
      }
    }
  }
}


@available (macOS 10.13, *)
class NowPlayingInfoManager {
  static let info = MPNowPlayingInfoCenter.default()

  static func updateInfo() {
    var nowPlayingInfo = [String: Any]()
    let activePlayer = PlayerCore.lastActive

    if activePlayer.currentMediaIsAudio == .isAudio {
      nowPlayingInfo[MPMediaItemPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
      let (title, album, artist) = activePlayer.getMusicMetadata()
      nowPlayingInfo[MPMediaItemPropertyTitle] = title
      nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
      nowPlayingInfo[MPMediaItemPropertyArtist] = artist
    } else {
      nowPlayingInfo[MPMediaItemPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
      nowPlayingInfo[MPMediaItemPropertyTitle] = activePlayer.getMediaTitle(withExtension: false)
    }

    let duration = PlayerCore.lastActive.info.videoDuration?.second ?? 0
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = activePlayer.info.videoPosition?.second ?? 0
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = activePlayer.info.playSpeed
    nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1
    /*
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = activePlayer.mpv.getInt(MPVProperty.playlistCount)
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = activePlayer.mpv.getInt(MPVProperty.playlistPos)
    nowPlayingInfo[MPNowPlayingInfoPropertyChapterCount] = activePlayer.mpv.getInt(MPVProperty.chapterListCount)
    nowPlayingInfo[MPNowPlayingInfoPropertyChapterNumber] = activePlayer.mpv.getInt(MPVProperty.chapter)
    */
    info.nowPlayingInfo = nowPlayingInfo
  }

  static func updateState(_ state: MPNowPlayingPlaybackState) {
    info.playbackState = state
  }

}
