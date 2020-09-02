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

  static var playing: [PlayerCore] {
    return playerCores.filter { !$0.info.isIdle }
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
    pc.loadPlugins()
    playerCoreCounter += 1
    return pc
  }

  static func activeOrNewForMenuAction(isAlternative: Bool) -> PlayerCore {
    let useNew = Preference.bool(for: .alwaysOpenInNewWindow) != isAlternative
    return useNew ? newPlayerCore : active
  }

  // MARK: - Fields

  lazy var subsystem = Logger.Subsystem(rawValue: "player\(label!)")

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
  var plugins: [JavascriptPluginInstance] = []
  private var pluginMap: [String: JavascriptPluginInstance] = [:]
  var events = EventController()

  lazy var ffmpegController: FFmpegController = {
    let controller = FFmpegController()
    controller.delegate = self
    return controller
  }()

  lazy var info: PlaybackInfo = PlaybackInfo(self)

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

  var isPlaylistVisible: Bool {
    isInMiniPlayer ? miniPlayer.isPlaylistVisible : mainWindow.sideBarStatus == .playlist
  }

  static var keyBindings: [String: KeyMapping] = [:]

  override init() {
    super.init()
    self.mpv = MPVController(playerCore: self)
    self.mainWindow = MainWindowController(playerCore: self)
    self.miniPlayer = MiniPlayerWindowController(playerCore: self)
    self.initialWindow = InitialWindowController(playerCore: self)
    if #available(macOS 10.12.2, *) {
      self._touchBarSupport = TouchBarSupport(playerCore: self)
    }
  }

  // MARK: - Plugins

  static func reloadPluginForAll(_ plugin: JavascriptPlugin) {
    playerCores.forEach { $0.reloadPlugin(plugin) }
    (NSApp.delegate as? AppDelegate)?.menuController?.updatePluginMenu()
  }

  func loadPlugins() {
    pluginMap.removeAll()
    plugins = JavascriptPlugin.plugins.compactMap { plugin in
      guard plugin.enabled else { return nil }
      let instance = JavascriptPluginInstance(player: self, plugin: plugin)
      pluginMap[plugin.identifier] = instance
      return instance
    }
  }

  func reloadPlugin(_ plugin: JavascriptPlugin, forced: Bool = false) {
    let id = plugin.identifier
    if let _ = pluginMap[id] {
      if plugin.enabled {
        // no need to reload, unless forced
        guard forced else { return }
        pluginMap[id] = JavascriptPluginInstance(player: self, plugin: plugin)
      } else {
        pluginMap.removeValue(forKey: id)
      }
    } else {
      guard plugin.enabled else { return }
      pluginMap[id] = JavascriptPluginInstance(player: self, plugin: plugin)
    }

    plugins = JavascriptPlugin.plugins.compactMap { pluginMap[$0.identifier] }
  }

  // MARK: - Control

  private func open(_ url: URL?, shouldAutoLoad: Bool = false) {
    guard let url = url else {
      Logger.log("empty file path or url", level: .error, subsystem: subsystem)
      return
    }
    Logger.log("Open URL: \(url.absoluteString)", subsystem: subsystem)
    let isNetwork = !url.isFileURL
    if shouldAutoLoad {
      info.shouldAutoLoadFiles = true
    }
    let path = isNetwork ? url.absoluteString : url.path
    openMainWindow(path: path, url: url, isNetwork: isNetwork)
  }

  /**
   Open a list of urls. If there are more than one urls, add the remaining ones to
   playlist and disable auto loading.

   - Returns: `nil` if no further action is needed, like opened a BD Folder; otherwise the
   count of playable files.
   */
  @discardableResult
  func openURLs(_ urls: [URL], shouldAutoLoad autoLoad: Bool = true) -> Int? {
    guard !urls.isEmpty else { return 0 }
    let urls = Utility.resolveURLs(urls)

    // handle BD folders and m3u / m3u8 files first
    if urls.count == 1 && (isBDFolder(urls[0]) ||
      Utility.playlistFileExt.contains(urls[0].absoluteString.lowercasedPathExtension)) {
      info.shouldAutoLoadFiles = false
      open(urls[0])
      return nil
    }

    let playableFiles = getPlayableFiles(in: urls)
    let count = playableFiles.count

    // check playable files count
    if count == 0 {
      return 0
    }

    if !autoLoad {
      info.shouldAutoLoadFiles = false
    } else {
      info.shouldAutoLoadFiles = (count == 1)
    }

    // open the first file
    open(playableFiles[0])
    // add the remaining to playlist
    playableFiles[1..<count].forEach { url in
      addToPlaylist(url.isFileURL ? url.path : url.absoluteString)
    }

    // refresh playlist
    postNotification(.iinaPlaylistChanged)
    // send OSD
    if count > 1 {
      sendOSD(.addToPlaylist(count))
    }
    return count
  }

  func openURL(_ url: URL, shouldAutoLoad: Bool = true) {
    openURLs([url], shouldAutoLoad: shouldAutoLoad)
  }

  func openURLString(_ str: String) {
    if str == "-" {
      openMainWindow(path: str, url: URL(string: "stdin")!, isNetwork: false)
      return
    }
    if str.first == "/" {
      openURL(URL(fileURLWithPath: str))
    } else {
      guard let pstr = str.addingPercentEncoding(withAllowedCharacters: .urlAllowed), let url = URL(string: pstr) else {
        Logger.log("Cannot add percent encoding for \(str)", level: .error, subsystem: subsystem)
        return
      }
      openURL(url)
    }
  }


  private func openMainWindow(path: String, url: URL, isNetwork: Bool) {
    Logger.log("Opening \(path) in main window", subsystem: subsystem)
    info.currentURL = url
    // clear currentFolder since playlist is cleared, so need to auto-load again in playerCore#fileStarted
    info.currentFolder = nil
    info.isNetworkResource = isNetwork

    let isFirstLoad = !mainWindow.loaded
    let _ = mainWindow.window
    initialWindow.close()
    if isInMiniPlayer {
      miniPlayer.showWindow(nil)
    } else {
      // we only want to call windowWillOpen when the window is currently closed.
      // if the window is opened for the first time, it will become visible in windowDidLoad, so we need to check isFirstLoad.
      // window.isVisible will work from the second time.
      if isFirstLoad || !mainWindow.window!.isVisible {
        mainWindow.windowWillOpen()
      }
      mainWindow.showWindow(nil)
      mainWindow.windowDidOpen()
    }

    // Send load file command
    info.fileLoading = true
    info.justOpenedFile = true
    mpv.command(.loadfile, args: [path])
  }

  static func loadKeyBindings() {
    Logger.log("Loading key bindings")
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
    Logger.log("Set key bindings")
    var keyBindings: [String: KeyMapping] = [:]
    keyMappings.forEach { keyBindings[$0.key] = $0 }
    PlayerCore.keyBindings = keyBindings
    (NSApp.delegate as? AppDelegate)?.menuController.updateKeyEquivalentsFrom(Array(keyBindings.values))
  }

  func startMPV() {
    // set path for youtube-dl
    let oldPath = String(cString: getenv("PATH")!)
    var path = Utility.exeDirURL.path + ":" + oldPath
    if let customYtdlPath = Preference.string(for: .ytdlSearchPath), !customYtdlPath.isEmpty {
      path = customYtdlPath + ":" + path
    }
    setenv("PATH", path, 1)
    Logger.log("Set path to \(path)", subsystem: subsystem)

    // set http proxy
    if let proxy = Preference.string(for: .httpProxy), !proxy.isEmpty {
      setenv("http_proxy", "http://" + proxy, 1)
      Logger.log("Set http_proxy to \(proxy)", subsystem: subsystem)
    }

    mpv.mpvInit()
    events.emit(.mpvInitialized)

    if !getAudioDevices().contains(where: { $0["name"] == Preference.string(for: .audioDevice)! }) {
      setAudioDevice("auto")
    }
  }

  func initVideo() {
    // init mpv render context.
    // The video layer must be displayed once to get the OpenGL context initialized.
    mainWindow.videoView.videoLayer.display()
    mpv.mpvInitRendering()
    mainWindow.videoView.startDisplayLink()
  }

  // unload main window video view
  func uninitVideo() {
    guard mainWindow.loaded else { return }
    mainWindow.videoView.stopDisplayLink()
    mainWindow.videoView.uninit()
  }

  // Terminate mpv
  func terminateMPV(sendQuit: Bool = true) {
    guard !isMpvTerminated else { return }
    savePlaybackPosition()
    invalidateTimer()
    uninitVideo()
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
    Logger.log("Switch to mini player, automatically=\(automatically)", subsystem: subsystem)
    if !automatically {
      switchedToMiniPlayerManually = true
    }
    switchedBackFromMiniPlayerManually = false

    let needRestoreLayout = !miniPlayer.loaded
    miniPlayer.showWindow(self)

    miniPlayer.updateTitle()
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

    let (width, height) = originalVideoSize
    let aspect = (width == 0 || height == 0) ? 1 : CGFloat(width) / CGFloat(height)
    miniPlayer.updateVideoViewAspectConstraint(withAspect: aspect)

    // if received video size before switching to music mode, hide default album art
    if info.vid != 0 {
      miniPlayer.defaultAlbumArt.isHidden = true
    }
    // in case of video size changed, reset mini player window size if playlist is folded
    if !miniPlayer.isPlaylistVisible {
      miniPlayer.setToInitialWindowSize(display: true, animate: false)
    }

    // hide main window
    mainWindow.window?.orderOut(self)
    isInMiniPlayer = true

    videoView.videoLayer.draw(forced: true)

    // restore layout
    if needRestoreLayout {
      if !Preference.bool(for: .musicModeShowAlbumArt) {
        miniPlayer.toggleVideoView(self)
      }
      if Preference.bool(for: .musicModeShowPlaylist) {
        miniPlayer.togglePlaylist(self)
      }
    }
    
    events.emit(.musicModeChanged, data: true)
  }

  func switchBackFromMiniPlayer(automatically: Bool, showMainWindow: Bool = true) {
    Logger.log("Switch to normal window from mini player, automatically=\(automatically)", subsystem: subsystem)
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
    let (width, height) = originalVideoSize
    if width == 0 && height == 0 {
      mainWindow.window?.aspectRatio = AppData.sizeWhenNoVideo
    }
    // hide mini player
    miniPlayer.window?.orderOut(nil)
    isInMiniPlayer = false

    mainWindow.videoView.videoLayer.draw(forced: true)

    mainWindow.updateTitle()
    
    events.emit(.musicModeChanged, data: false)
  }

  // MARK: - MPV commands

  func togglePause(_ set: Bool? = nil) {
    info.isPaused ? resume() : pause()
  }

  func pause() {
    mpv.setFlag(MPVOption.PlaybackControl.pause, true)
  }

  func resume() {
    // Restart playback when reached EOF
    if mpv.getFlag(MPVProperty.eofReached) {
      seek(absoluteSecond: 0)
    }
    mpv.setFlag(MPVOption.PlaybackControl.pause, false)
  }

  func stop() {
    mpv.command(.stop)
    invalidateTimer()
  }

  func toggleMute(_ set: Bool? = nil) {
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
    guard let vid = info.vid, vid > 0 else { return }
    let saveToFile = Preference.bool(for: .screenshotSaveToFile)
    let saveToClipboard = Preference.bool(for: .screenshotCopyToClipboard)
    guard saveToFile || saveToClipboard else { return }

    let option = Preference.bool(for: .screenshotIncludeSubtitle) ? "subtitles" : "video"

    mpv.asyncCommand(.screenshot, args: [option], replyUserdata: MPVController.UserData.screenshot)
  }

  func screenshotCallback() {
    let saveToFile = Preference.bool(for: .screenshotSaveToFile)
    let saveToClipboard = Preference.bool(for: .screenshotCopyToClipboard)
    guard saveToFile || saveToClipboard else { return }

    guard let imageFolder = mpv.getString(MPVOption.Screenshot.screenshotDirectory) else { return }
    guard let lastScreenshotURL = Utility.getLatestScreenshot(from: imageFolder) else { return }
    guard let image = NSImage(contentsOf: lastScreenshotURL) else {
      self.sendOSD(.screenshot)
      return
    }
    if saveToClipboard {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([image])
    }
    guard Preference.bool(for: .screenshotShowPreview) else {
      self.sendOSD(.screenshot)
      return
    }

    DispatchQueue.main.async {
      let osdView = ScreenshootOSDView()
      osdView.setImage(image,
                       size: image.size.shrink(toSize: NSSize(width: 300, height: 200)),
                       fileURL: saveToFile ? lastScreenshotURL : nil)
      self.sendOSD(.screenshot, forcedTimeout: 5, accessoryView: osdView.view, context: osdView)
      if !saveToFile {
        try? FileManager.default.removeItem(at: lastScreenshotURL)
      }
    }
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

  func clearAbLoop() {
    if mpv.getFlag(MPVOption.PlaybackControl.abLoopA) {
      if mpv.getFlag(MPVOption.PlaybackControl.abLoopB) {
        info.abLoopStatus = 2
      } else {
        info.abLoopStatus = 1
      }
    } else {
      info.abLoopStatus = 0
    }
  }

  func toggleFileLoop() {
    let isLoop = mpv.getString(MPVOption.PlaybackControl.loopFile) == "inf"
    mpv.setString(MPVOption.PlaybackControl.loopFile, isLoop ? "no" : "inf")
    sendOSD(.fileLoop(!isLoop))
    events.emit(.playlistLoopChanged, data: !isLoop)
  }

  func togglePlaylistLoop() {
    let loopStatus = mpv.getString(MPVOption.PlaybackControl.loopPlaylist)
    let isLoop = (loopStatus == "inf" || loopStatus == "force")
    mpv.setString(MPVOption.PlaybackControl.loopPlaylist, isLoop ? "no" : "inf")
    sendOSD(.playlistLoop(!isLoop))
    events.emit(.playlistLoopChanged, data: !isLoop)
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
    if AppData.rotations.firstIndex(of: degree)! >= 0 {
      mpv.setInt(MPVOption.Video.videoRotate, degree)
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

  func toggleHardwareDecoding(_ enable: Bool) {
    let value = Preference.HardwareDecoderOption(rawValue: Preference.integer(for: .hardwareDecoder))?.mpvString ?? "auto"
    mpv.setString(MPVOption.Video.hwdec, enable ? value : "no")
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
  
  func loadExternalVideoFile(_ url: URL) {
    mpv.command(.videoAdd, args: [url.path], checkError: false) { code in
      if code < 0 {
        Logger.log("Unsupported video: \(url.path)", level: .error, subsystem: self.subsystem)
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_audio")
        }
      }
    }
  }

  func loadExternalAudioFile(_ url: URL) {
    mpv.command(.audioAdd, args: [url.path], checkError: false) { code in
      if code < 0 {
        Logger.log("Unsupported audio: \(url.path)", level: .error, subsystem: self.subsystem)
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
        Logger.log("Unsupported sub: \(url.path)", level: .error, subsystem: self.subsystem)
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
          Logger.log("Failed reloading subtitles: error code \(code)", level: .error, subsystem: self.subsystem)
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

  private func _addToPlaylist(_ path: String) {
    mpv.command(.loadfile, args: [path, "append"])
  }

  func addToPlaylist(_ path: String) {
    _addToPlaylist(path)
    postNotification(.iinaPlaylistChanged)
  }

  private func _playlistMove(_ from: Int, to: Int) {
    mpv.command(.playlistMove, args: ["\(from)", "\(to)"])
  }

  func playlistMove(_ from: Int, to: Int) {
    _playlistMove(from, to: to)
    postNotification(.iinaPlaylistChanged)
  }

  func addToPlaylist(paths: [String], at index: Int = -1) {
    getPlaylist()
    for path in paths {
      _addToPlaylist(path)
    }
    if index <= info.playlist.count && index >= 0 {
      let previousCount = info.playlist.count
      for i in 0..<paths.count {
        playlistMove(previousCount + i, to: index + i)
      }
    }
    postNotification(.iinaPlaylistChanged)
  }

  private func _playlistRemove(_ index: Int) {
    mpv.command(.playlistRemove, args: [index.description])
  }

  func playlistRemove(_ index: Int) {
    _playlistRemove(index)
    postNotification(.iinaPlaylistChanged)
  }

  func playlistRemove(_ indexSet: IndexSet) {
    var count = 0
    for i in indexSet {
      _playlistRemove(i - count)
      count += 1
    }
    postNotification(.iinaPlaylistChanged)
  }

  func clearPlaylist() {
    mpv.command(.playlistClear)
    postNotification(.iinaPlaylistChanged)
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
    resume()
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

  func setAudioEq(fromGains gains: [Double]) {
    let channelCount = mpv.getInt(MPVProperty.audioParamsChannelCount)
    let freqList = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    let filters = freqList.enumerated().map { (index, freq) -> MPVFilter in
      let string = [Int](0..<channelCount).map { "c\($0) f=\(freq) w=\(freq / 1.224744871) g=\(gains[index])" }.joined(separator: "|")
      return MPVFilter(name: "lavfi", label: "\(Constants.FilterName.audioEq)\(index)", paramString: "[anequalizer=\(string)]")
    }
    filters.forEach { _ = addAudioFilter($0) }
    info.audioEqFilters = filters
  }

  func removeAudioEqFilter() {
    info.audioEqFilters?.compactMap { $0 }.forEach { _ = removeAudioFilter($0) }
    info.audioEqFilters = nil
  }

  /// Add a video filter given as a `MPVFilter` object.
  ///
  /// This method will prompt the user to change IINA's video preferences if hardware decoding is set to `auto`.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  func addVideoFilter(_ filter: MPVFilter) -> Bool { addVideoFilter(filter.stringFormat) }

  /// Add a video filter given as a string.
  ///
  /// This method will prompt the user to change IINA's video preferences if hardware decoding is set to `auto`.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  func addVideoFilter(_ filter: String) -> Bool {
    Logger.log("Adding video filter \(filter)...", subsystem: subsystem)
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
    mpv.command(.vf, args: ["add", filter], checkError: false) { result = $0 >= 0 }
    Logger.log(result ? "Succeeded" : "Failed", subsystem: self.subsystem)
    return result
  }

  /// Remove a video filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeVideoFilter(_ filter: MPVFilter, _ index: Int) -> Bool {
    removeVideoFilter(filter.stringFormat, index)
  }

  /// Remove a video filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeVideoFilter(_ filter: String, _ index: Int) -> Bool {
    Logger.log("Removing video filter \(filter)...", subsystem: subsystem)
    let result = mpv.removeFilter(MPVProperty.vf, index)
    Logger.log(result ? "Succeeded" : "Failed", subsystem: self.subsystem)
    return result
  }

  /// Remove a video filter given as a `MPVFilter` object.
  ///
  /// If the filter is not labeled then removing using a `MPVFilter` object can be problematic if the filter has multiple parameters.
  /// Filters that support multiple parameters have more than one valid string representation due to there being no requirement on the
  /// order in which those parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in
  /// the command sent to mpv does not match the order mpv expects the remove command will not find the filter to be removed. For
  /// this reason the remove methods that identify the filter to be removed based on its position in the filter list are the preferred way to
  /// remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeVideoFilter(_ filter: MPVFilter) -> Bool {
    if let label = filter.label {
      return removeVideoFilter("@" + label)
    }
    return removeVideoFilter(filter.stringFormat)
  }

  /// Remove a video filter given as a string.
  ///
  /// If the filter is not labeled then removing using a string can be problematic if the filter has multiple parameters. Filters that support
  /// multiple parameters have more than one valid string representation due to there being no requirement on the order in which those
  /// parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in the command sent to
  /// mpv does not match the order mpv expects the remove command will not find the filter to be removed. For this reason the remove
  /// methods that identify the filter to be removed based on its position in the filter list are the preferred way to remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeVideoFilter(_ filter: String) -> Bool {
    Logger.log("Removing video filter \(filter)...", subsystem: subsystem)
    var result = true
    mpv.command(.vf, args: ["remove", filter], checkError: false) { result = $0 >= 0 }
    Logger.log(result ? "Succeeded" : "Failed", subsystem: self.subsystem)
    return result
  }

  /// Add an audio filter given as a `MPVFilter` object.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  func addAudioFilter(_ filter: MPVFilter) -> Bool { addAudioFilter(filter.stringFormat) }

  /// Add an audio filter given as a string.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  func addAudioFilter(_ filter: String) -> Bool {
    Logger.log("Adding audio filter \(filter)...", subsystem: subsystem)
    var result = true
    mpv.command(.af, args: ["add", filter], checkError: false) { result = $0 >= 0 }
    Logger.log(result ? "Succeeded" : "Failed", subsystem: self.subsystem)
    return result
  }

  /// Remove an audio filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeAudioFilter(_ filter: MPVFilter, _ index: Int) -> Bool {
    removeAudioFilter(filter.stringFormat, index)
  }

  /// Remove an audio filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeAudioFilter(_ filter: String, _ index: Int) -> Bool {
    Logger.log("Removing audio filter \(filter)...", subsystem: subsystem)
    let result = mpv.removeFilter(MPVProperty.af, index)
    Logger.log(result ? "Succeeded" : "Failed", subsystem: self.subsystem)
    return result
  }

  /// Remove an audio filter given as a `MPVFilter` object.
  ///
  /// If the filter is not labeled then removing using a `MPVFilter` object can be problematic if the filter has multiple parameters.
  /// Filters that support multiple parameters have more than one valid string representation due to there being no requirement on the
  /// order in which those parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in
  /// the command sent to mpv does not match the order mpv expects the remove command will not find the filter to be removed. For
  /// this reason the remove methods that identify the filter to be removed based on its position in the filter list are the preferred way to
  /// remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeAudioFilter(_ filter: MPVFilter) -> Bool { removeAudioFilter(filter.stringFormat) }

  /// Remove an audio filter given as a string.
  ///
  /// If the filter is not labeled then removing using a string can be problematic if the filter has multiple parameters. Filters that support
  /// multiple parameters have more than one valid string representation due to there being no requirement on the order in which those
  /// parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in the command sent to
  /// mpv does not match the order mpv expects the remove command will not find the filter to be removed. For this reason the remove
  /// methods that identify the filter to be removed based on its position in the filter list are the preferred way to remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeAudioFilter(_ filter: String) -> Bool {
    Logger.log("Removing audio filter \(filter)...", subsystem: subsystem)
    var result = true
    mpv.command(.af, args: ["remove", filter], checkError: false)  { result = $0 >= 0 }
    Logger.log(result ? "Succeeded" : "Failed", subsystem: self.subsystem)
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
        Logger.log("Error when executing key code (\(errCode))", level: .error, subsystem: self.subsystem)
      }
    }
  }

  func savePlaybackPosition() {
    guard Preference.bool(for: .resumeLastPosition) else { return }
    Logger.log("Write watch later config", subsystem: subsystem)
    mpv.command(.writeWatchLaterConfig)
    if let url = info.currentURL {
      Preference.set(url, for: .iinaLastPlayedFilePath)
      // Write to cache directly (rather than calling `refreshCachedVideoProgress`).
      // If user only closed the window but didn't quit the app, this can make sure playlist displays the correct progress.
      info.setCachedVideoDurationAndProgress(url.path, (duration: info.videoDuration?.second, progress: info.videoPosition?.second))
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

  func fileStarted(path: String) {
    Logger.log("File started", subsystem: subsystem)
    info.justStartedFile = true
    info.disableOSDForFileLoading = true
    currentMediaIsAudio = .unknown

    info.currentURL = path.contains("://") ?
      URL(string: path.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? path) :
      URL(fileURLWithPath: path)
    info.isNetworkResource = !info.currentURL!.isFileURL

    // set "date last opened" attribute
    if let url = info.currentURL, url.isFileURL {
      // the required data is a timespec struct
      var ts = timespec()
      let time = Date().timeIntervalSince1970
      ts.tv_sec = Int(time)
      ts.tv_nsec = Int(time.truncatingRemainder(dividingBy: 1) * 1_000_000_000)
      let data = Data(bytesOf: ts)
      // set the attribute; the key is undocumented
      let name = "com.apple.lastuseddate#PS"
      url.withUnsafeFileSystemRepresentation { fileSystemPath in
        let _ = data.withUnsafeBytes {
          setxattr(fileSystemPath, name, $0.baseAddress, data.count, 0, 0)
        }
      }
    }

    if #available(OSX 10.13, *), RemoteCommandController.useSystemMediaControl {
      DispatchQueue.main.async {
        NowPlayingInfoManager.updateInfo(state: .playing, withTitle: true)
      }
    }

    // Auto load
    backgroundQueueTicket += 1
    let shouldAutoLoadFiles = info.shouldAutoLoadFiles
    let currentTicket = backgroundQueueTicket
    backgroundQueue.async {
      // add files in same folder
      if shouldAutoLoadFiles {
        Logger.log("Started auto load", subsystem: self.subsystem)
        self.autoLoadFilesInCurrentFolder(ticket: currentTicket)
      }
      // auto load matched subtitles
      if let matchedSubs = self.info.matchedSubs[path] {
        Logger.log("Found \(matchedSubs.count) subs for current file", subsystem: self.subsystem)
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
    events.emit(.fileStarted)
  }

  /** This function is called right after file loaded. Should load all meta info here. */
  func fileLoaded() {
    Logger.log("File loaded", subsystem: subsystem)
    invalidateTimer()
    triedUsingExactSeekForCurrentFile = false
    info.fileLoading = false
    info.haveDownloadedSub = false
    checkUnsyncedWindowOptions()
    // generate thumbnails if window has loaded video
    if mainWindow.isVideoLoaded {
      generateThumbnails()
    }
    // call `trackListChanged` to load tracks and check whether need to switch to music mode
    trackListChanged()
    // main thread stuff
    DispatchQueue.main.sync {
      getPlaylist()
      getChapters()
      clearAbLoop()
      createSyncUITimer()
      if #available(macOS 10.12.2, *) {
        touchBarSupport.setupTouchBarUI()
      }

      if info.aid == 0 {
        mainWindow.muteButton.isEnabled = false
        mainWindow.volumeSlider.isEnabled = false
      }

      if info.vid == 0 {
        notifyMainWindowVideoSizeChanged()
      }

      if self.isInMiniPlayer {
        miniPlayer.defaultAlbumArt.isHidden = self.info.vid != 0
      }
    }
    // set initial properties for the first file
    if info.justLaunched {
      if Preference.bool(for: .fullScreenWhenOpen) && !mainWindow.fsState.isFullscreen && !isInMiniPlayer {
        DispatchQueue.main.async(execute: self.mainWindow.toggleWindowFullScreen)
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
    events.emit(.fileLoaded, data: info.currentURL ?? "")
  }

  func playbackRestarted() {
    Logger.log("Playback restarted", subsystem: subsystem)
    reloadSavedIINAfilters()
    mainWindow.videoView.videoLayer.draw(forced: true)

    if #available(OSX 10.13, *), RemoteCommandController.useSystemMediaControl {
      NowPlayingInfoManager.updateInfo()
    }


    DispatchQueue.main.async {
      Timer.scheduledTimer(timeInterval: TimeInterval(0.2), target: self, selector: #selector(self.reEnableOSDAfterFileLoading), userInfo: nil, repeats: false)
    }
  }

  func trackListChanged() {
    Logger.log("Track list changed", subsystem: subsystem)
    getTrackInfo()
    getSelectedTracks()
    let audioStatusWasUnkownBefore = currentMediaIsAudio == .unknown
    currentMediaIsAudio = checkCurrentMediaIsAudio()
    let audioStatusIsAvailableNow = currentMediaIsAudio != .unknown && audioStatusWasUnkownBefore
    // if need to switch to music mode
    if audioStatusIsAvailableNow && Preference.bool(for: .autoSwitchToMusicMode) {
      if currentMediaIsAudio == .isAudio {
        if !isInMiniPlayer && !mainWindow.fsState.isFullscreen && !switchedBackFromMiniPlayerManually {
          Logger.log("Current media is audio, switch to mini player", subsystem: subsystem)
          DispatchQueue.main.sync {
            switchToMiniPlayer(automatically: true)
          }
        }
      } else {
        if isInMiniPlayer && !switchedToMiniPlayerManually {
          Logger.log("Current media is not audio, switch to normal window", subsystem: subsystem)
          DispatchQueue.main.sync {
            switchBackFromMiniPlayer(automatically: true)
          }
        }
      }
    }
  }

  @available(macOS 10.15, *)
  func refreshEdrMode() {
    guard mainWindow.loaded else { return }
    DispatchQueue.main.async {
      self.mainWindow.videoView.refreshEdrMode()
    }
  }

  @objc
  private func reEnableOSDAfterFileLoading() {
    info.disableOSDForFileLoading = false
  }

  private func autoSearchOnlineSub() {
    Thread.sleep(forTimeInterval: 0.5)
    if Preference.bool(for: .autoSearchOnlineSub) &&
      !info.isNetworkResource && info.subTracks.isEmpty &&
      (info.videoDuration?.second ?? 0.0) >= Preference.double(for: .autoSearchThreshold) * 60 {
      DispatchQueue.main.async {
        self.mainWindow.menuActionHandler.menuFindOnlineSub(.dummy)
      }
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

  /**
   Checks unsynchronized window options, such as those set via mpv before window loaded.

   These options currently include fullscreen and ontop.
   */
  private func checkUnsyncedWindowOptions() {
    guard mainWindow.loaded else { return }

    let fs = mpv.getFlag(MPVOption.Window.fullscreen)
    if fs != mainWindow.fsState.isFullscreen {
      DispatchQueue.main.async {
        self.mainWindow.toggleWindowFullScreen()
      }
    }

    let ontop = mpv.getFlag(MPVOption.Window.ontop)
    if ontop != mainWindow.isOntop {
      DispatchQueue.main.async {
        self.mainWindow.setWindowFloatingOnTop(ontop, updateOnTopStatus: false)
      }
    }
  }

  // MARK: - Sync with UI in MainWindow

  func createSyncUITimer() {
    invalidateTimer()
    syncPlayTimeTimer = Timer.scheduledTimer(
      timeInterval: TimeInterval(DurationDisplayTextField.precision >= 2 ? AppData.syncTimePreciseInterval : AppData.syncTimeInterval),
      target: self,
      selector: #selector(self.syncUITime),
      userInfo: nil,
      repeats: true
    )
  }

  func notifyMainWindowVideoSizeChanged() {
    mainWindow.adjustFrameByVideoSize()
    if isInMiniPlayer {
      miniPlayer.updateVideoSize()
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
    case playlistLoop
//    case fileLoop
    case additionalInfo
  }

  @objc func syncUITime() {
    if info.isNetworkResource {
      syncUI(.timeAndCache)
    } else {
      syncUI(.time)
    }
    if !isInMiniPlayer &&
      mainWindow.fsState.isFullscreen && mainWindow.displayTimeAndBatteryInFullScreen &&
      !mainWindow.additionalInfoView.isHidden {
        syncUI(.additionalInfo)
    }
  }

  func syncUI(_ option: SyncUIOption) {
    // if window not loaded, ignore
    guard mainWindow.loaded else { return }
    Logger.log("Syncing UI \(option)", level: .verbose, subsystem: subsystem)

    switch option {

    case .time:
      info.videoPosition?.second = mpv.getDouble(MPVProperty.timePos)
      if info.isNetworkResource {
        info.videoDuration?.second = mpv.getDouble(MPVProperty.duration)
      }
      // When the end of a video file is reached mpv does not update the value of the property
      // time-pos, leaving it reflecting the position of the last frame of the video. This is
      // especially noticeable if the onscreen controller time labels are configured to show
      // milliseconds. Adjust the position if the end of the file has been reached.
      let eofReached = mpv.getFlag(MPVProperty.eofReached)
      if eofReached, let duration = info.videoDuration?.second {
        info.videoPosition?.second = duration
      }
      info.constrainVideoPosition()
      DispatchQueue.main.async {
        if self.isInMiniPlayer {
          self.miniPlayer.updatePlayTime(withDuration: self.info.isNetworkResource, andProgressBar: true)
        } else {
          self.mainWindow.updatePlayTime(withDuration: self.info.isNetworkResource, andProgressBar: true)
        }
      }

    case .timeAndCache:
      info.videoPosition?.second = mpv.getDouble(MPVProperty.timePos)
      info.videoDuration?.second = mpv.getDouble(MPVProperty.duration)
      // When the end of a video file is reached mpv does not update the value of the property
      // time-pos, leaving it reflecting the position of the last frame of the video. This is
      // especially noticeable if the onscreen controller time labels are configured to show
      // milliseconds. Adjust the position if the end of the file has been reached.
      let eofReached = mpv.getFlag(MPVProperty.eofReached)
      if eofReached, let duration = info.videoDuration?.second {
        info.videoPosition?.second = duration
      }
      info.constrainVideoPosition()
      info.pausedForCache = mpv.getFlag(MPVProperty.pausedForCache)
      info.cacheUsed = ((mpv.getNode(MPVProperty.demuxerCacheState) as? [String: Any])?["fw-bytes"] as? Int) ?? 0
      info.cacheSpeed = mpv.getInt(MPVProperty.cacheSpeed)
      info.cacheTime = mpv.getInt(MPVProperty.demuxerCacheTime)
      info.bufferingState = mpv.getInt(MPVProperty.cacheBufferingState)
      DispatchQueue.main.async {
        if self.isInMiniPlayer {
          self.miniPlayer.updatePlayTime(withDuration: true, andProgressBar: true)
        } else {
          self.mainWindow.updatePlayTime(withDuration: true, andProgressBar: true)
        }
        self.mainWindow.updateNetworkState()
      }

    case .playButton:
      DispatchQueue.main.async {
        self.mainWindow.updatePlayButtonState(self.info.isPaused ? .off : .on)
        self.miniPlayer.updatePlayButtonState(self.info.isPaused ? .off : .on)
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
        if self.isPlaylistVisible {
          self.mainWindow.playlistView.playlistTableView.reloadData()
        }
      }

    case .playlistLoop:
      DispatchQueue.main.async {
        self.mainWindow.playlistView.updateLoopBtnStatus()
      }

    case .additionalInfo:
      DispatchQueue.main.async {
        self.mainWindow.updateAdditionalInfo()
      }
    }
  }

  func sendOSD(_ osd: OSDMessage, autoHide: Bool = true, forcedTimeout: Float? = nil, accessoryView: NSView? = nil, context: Any? = nil, external: Bool = false) {
    // querying `mainWindow.isWindowLoaded` will initialize mainWindow unexpectly
    guard mainWindow.loaded && Preference.bool(for: .enableOSD) else { return }
    if info.disableOSDForFileLoading && !external {
      guard case .fileStart = osd else {
        return
      }
    }
    DispatchQueue.main.async {
      self.mainWindow.displayOSD(osd,
                                 autoHide: autoHide,
                                 forcedTimeout: forcedTimeout,
                                 accessoryView: accessoryView,
                                 context: context)
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
    Logger.log("Getting thumbnails", subsystem: subsystem)
    info.thumbnailsReady = false
    info.thumbnails.removeAll(keepingCapacity: true)
    info.thumbnailsProgress = 0
    if #available(macOS 10.12.2, *) {
      DispatchQueue.main.async {
        self.touchBarSupport.touchBarPlaySlider?.resetCachedThumbnails()
      }
    }
    guard !info.isNetworkResource, let url = info.currentURL else {
      Logger.log("...stopped because cannot get file path", subsystem: subsystem)
      return
    }
    if !Preference.bool(for: .enableThumbnailForRemoteFiles) {
      if let attrs = try? url.resourceValues(forKeys: Set([.volumeIsLocalKey])), !attrs.volumeIsLocal! {
        Logger.log("...stopped because file is on a mounted remote drive", subsystem: subsystem)
        return
      }
    }
    if Preference.bool(for: .enableThumbnailPreview) {
      if let cacheName = info.mpvMd5, ThumbnailCache.fileIsCached(forName: cacheName, forVideo: info.currentURL) {
        Logger.log("Found thumbnail cache", subsystem: subsystem)
        thumbnailQueue.async {
          if let thumbnails = ThumbnailCache.read(forName: cacheName) {
            self.info.thumbnails = thumbnails
            self.info.thumbnailsReady = true
            self.info.thumbnailsProgress = 1
            self.refreshTouchBarSlider()
          } else {
            Logger.log("Cannot read thumbnail from cache", level: .error, subsystem: self.subsystem)
          }
        }
      } else {
        Logger.log("Request new thumbnails", subsystem: subsystem)
        ffmpegController.generateThumbnail(forFile: url.path, thumbWidth:Int32(Preference.integer(for: .thumbnailWidth)))
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
        Logger.log("videoSizeForDisplay: Cannot get dwidth and dheight", level: .warning, subsystem: subsystem)
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
    if mpv.getInt(MPVProperty.chapters) > 0 {
      let chapter = mpv.getInt(MPVProperty.chapter)
      let chapterTitle = mpv.getString(MPVProperty.chapterListNTitle(chapter))
      return (
        chapterTitle ?? mpv.getString(MPVProperty.mediaTitle) ?? "",
        mpv.getString("metadata/by-key/album") ?? "",
        mpv.getString("chapter-metadata/by-key/performer") ?? mpv.getString("metadata/by-key/artist") ?? ""
      )
    } else {
      return (
        mpv.getString(MPVProperty.mediaTitle) ?? "",
        mpv.getString("metadata/by-key/album") ?? "",
        mpv.getString("metadata/by-key/artist") ?? ""
      )
    }
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
      if label.hasPrefix(Constants.FilterName.audioEq) {
        if info.audioEqFilters == nil {
          info.audioEqFilters = Array(repeating: nil, count: 10)
        }
        if let index = Int(String(label.last!)) {
          info.audioEqFilters![index] = filter
        }
      }
    }
  }

  /**
   Get video duration, playback progress, and metadata, then save it to info.
   It may take some time to run this method, so it should be used in background.
   */
  func refreshCachedVideoInfo(forVideoPath path: String) {
    guard let dict = FFmpegController.probeVideoInfo(forFile: path) else { return }
    let progress = Utility.playbackProgressFromWatchLater(path.md5)
    self.info.setCachedVideoDurationAndProgress(path, (
      duration: dict["@iina_duration"] as? Double,
      progress: progress?.second
    ))
    var result: (title: String?, album: String?, artist: String?)
    dict.forEach { (k, v) in
      guard let key = k as? String else { return }
      switch key.lowercased() {
      case "title":
        result.title = v as? String
      case "album":
        result.album = v as? String
      case "artist":
        result.artist = v as? String
      default:
        break
      }
    }
    self.info.setCachedMetadata(path, result)
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
    for player in playing {
      if player.info.isPlaying {
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
    Logger.log("Got new thumbnails, progress \(progress)", subsystem: subsystem)
    if let thumbnails = thumbnails {
      info.thumbnails.append(contentsOf: thumbnails)
    }
    info.thumbnailsProgress = Double(progress) / Double(ffmpegController.thumbnailCount)
    refreshTouchBarSlider()
  }

  func didGenerate(_ thumbnails: [FFThumbnail], forFile filename: String, succeeded: Bool) {
    guard let currentFilePath = info.currentURL?.path, currentFilePath == filename else { return }
    Logger.log("Got all thumbnails, succeeded=\(succeeded)", subsystem: subsystem)
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
      events.emit(.thumbnailsReady)
    }
  }
}


@available (macOS 10.13, *)
class NowPlayingInfoManager {
  static private let lock = NSLock()

  static func updateInfo(state: MPNowPlayingPlaybackState? = nil, withTitle: Bool = false) {
    // This method is called from the main thread and from background threads. Must single thread access.
    lock.lock()
    defer {
      lock.unlock()
    }
    let center = MPNowPlayingInfoCenter.default()
    var info = center.nowPlayingInfo ?? [String: Any]()

    let activePlayer = PlayerCore.lastActive

    if withTitle {
      if activePlayer.currentMediaIsAudio == .isAudio {
        info[MPMediaItemPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        let (title, album, artist) = activePlayer.getMusicMetadata()
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyAlbumTitle] = album
        info[MPMediaItemPropertyArtist] = artist
      } else {
        info[MPMediaItemPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        info[MPMediaItemPropertyTitle] = activePlayer.getMediaTitle(withExtension: false)
      }
    }

    let duration = PlayerCore.lastActive.info.videoDuration?.second ?? 0
    let time = activePlayer.info.videoPosition?.second ?? 0
    let speed = activePlayer.info.playSpeed

    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
    info[MPNowPlayingInfoPropertyPlaybackRate] = speed
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1

    center.nowPlayingInfo = info

    if state != nil {
      center.playbackState = state!
    }
  }
}
