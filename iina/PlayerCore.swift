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

  /// Minimum value to set a mpv loop point to.
  ///
  /// Setting a loop point to zero disables looping, so when loop points are being adjusted IINA must insure the mpv property is not
  /// set to zero. However using `Double.leastNonzeroMagnitude` as the minimum value did not work because mpv truncates
  /// the value when storing the A-B loop points in the watch later file. As a result the state of the A-B loop feature is not properly
  /// restored when the movies is played again. Using the following value as the minimum for loop points avoids this issue.
  static private let minLoopPointTime = 0.000001

  // MARK: - Multiple instances

  static let first: PlayerCore = createPlayerCore()

  static private weak var _lastActive: PlayerCore?

  /// - Important: Code referencing this property **must** be run on the main thread as getting the value of this property _may_
  ///              result in a reference the `active` property and that requires use of the main thread.
  static var lastActive: PlayerCore {
    get {
      return _lastActive ?? active
    }
    set {
      _lastActive = newValue
    }
  }

  /// - Important: Code referencing this property **must** be run on the main thread because it references
  ///              [NSApplication.mainWindow`](https://developer.apple.com/documentation/appkit/nsapplication/1428723-mainwindow)
  static var active: PlayerCore {
    if let wc = NSApp.mainWindow?.windowController as? PlayerWindowController {
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
    return playerCores.filter { $0.info.state != .idle }
  }

  static var playerCores: [PlayerCore] = []
  static private var playerCoreCounter = 0

  static private func findIdlePlayerCore() -> PlayerCore? {
    playerCores.first { $0.info.state == .idle && !$0.backgroundTaskInUse }
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

  lazy var subsystem = Logger.makeSubsystem("player\(label!)")

  func log(_ message: String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: subsystem)
  }

  var label: String!
  var isManagedByPlugin = false
  var userLabel: String?
  var disableUI = false
  var disableWindowAnimation = false

  var touchBarSupport: TouchBarSupport {
    get {
      return self._touchBarSupport as! TouchBarSupport
    }
  }
  private var _touchBarSupport: Any?

  /// `true` if this Mac is known to have a touch bar.
  ///
  /// - Note: This is set based on whether `AppKit` has called `MakeTouchBar`, therefore it can, for example, be `false` for
  ///         a MacBook that has a touch bar if the touch bar is asleep because the Mac is in closed clamshell mode.
  var needsTouchBar = false

  /// A dispatch queue for auto load feature.
  let backgroundQueue: DispatchQueue
  let playlistQueue: DispatchQueue
  let thumbnailQueue: DispatchQueue

  /**
   This ticket will be increased each time before a new task being submitted to `backgroundQueue`.

   Each task holds a copy of ticket value at creation, so that a previous task will perceive and
   quit early if new tasks is awaiting.

   **See also**:

   `autoLoadFilesInCurrentFolder(ticket:)`
   */
  @Atomic var backgroundQueueTicket = 0

  enum TicketExpiredError: Error {
    case ticketExpired
  }

  private var backgroundTaskInUse = false

  var initialWindow: InitialWindowController!
  
  var mainWindow: MainWindowController!
  var miniPlayer: MiniPlayerWindowController!
  
  var currentController: PlayerWindowController {
    return isInMiniPlayer ? miniPlayer : mainWindow
  }

  var currentWindow: NSWindow? {
    currentController.window
  }

  var mpv: MPVController!

  var receivedEndFileWhileLoading: Bool = false

  var plugins: [JavascriptPluginInstance] = []
  private var pluginMap: [String: JavascriptPluginInstance] = [:]
  var events = EventController()

  lazy var ffmpegController: FFmpegController = {
    let controller = FFmpegController()
    controller.delegate = self
    return controller
  }()

  lazy var info: PlaybackInfo = PlaybackInfo(self)

  var syncUITimer: Timer?

  var displayOSD: Bool = true

  var isInMiniPlayer = false
  /// Set this to `true` if user changes "music mode" status manually. This disables `autoSwitchToMusicMode`
  /// functionality for the duration of this player even if the preference is `true`. But if they manually change the
  /// "music mode" status again, change this to `false` so that the preference is honored again.
  var overrideAutoSwitchToMusicMode = false

  var isSearchingOnlineSubtitle = false

  /// For supporting mpv `--shuffle` arg, to shuffle playlist when launching from command line
  @Atomic private var shufflePending = false

  // test seeking
  var triedUsingExactSeekForCurrentFile: Bool = false
  var useExactSeekForCurrentFile: Bool = true

  var isPlaylistVisible: Bool {
    isInMiniPlayer ? miniPlayer.isPlaylistVisible : mainWindow.sideBarStatus == .playlist
  }

  /// The A loop point established by the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  var abLoopA: Double {
    /// Returns the value of the A loop point, a timestamp in seconds if set, otherwise returns zero.
    /// - Note: The value of the A loop point is not required by mpv to be before the B loop point.
    /// - Returns:value of the mpv option `ab-loop-a`
    get { mpv.getDouble(MPVOption.PlaybackControl.abLoopA) }
    /// Sets the value of the A loop point as an absolute timestamp in seconds.
    ///
    /// The loop points of the mpv A-B loop command can be adjusted at runtime. This method updates the A loop point. Setting a
    /// loop point to zero disables looping, so this method will adjust the value so it is not equal to zero in order to require use of the
    /// A-B command to disable looping.
    /// - Precondition: The A loop point must have already been established using the A-B loop command otherwise the attempt
    ///     to change the loop point will be ignored.
    /// - Note: The value of the A loop point is not required by mpv to be before the B loop point.
    set {
      guard info.abLoopStatus == .aSet || info.abLoopStatus == .bSet else { return }
      mpv.setDouble(MPVOption.PlaybackControl.abLoopA, max(PlayerCore.minLoopPointTime, newValue))
    }
  }

  /// The B loop point established by the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  var abLoopB: Double {
    /// Returns the value of the B loop point, a timestamp in seconds if set, otherwise returns zero.
    /// - Note: The value of the B loop point is not required by mpv to be after the A loop point.
    /// - Returns:value of the mpv option `ab-loop-b`
    get { mpv.getDouble(MPVOption.PlaybackControl.abLoopB) }
    /// Sets the value of the B loop point as an absolute timestamp in seconds.
    ///
    /// The loop points of the mpv A-B loop command can be adjusted at runtime. This method updates the B loop point. Setting a
    /// loop point to zero disables looping, so this method will adjust the value so it is not equal to zero in order to require use of the
    /// A-B command to disable looping.
    /// - Precondition: The B loop point must have already been established using the A-B loop command otherwise the attempt
    ///     to change the loop point will be ignored.
    /// - Note: The value of the B loop point is not required by mpv to be after the A loop point.
    set {
      guard info.abLoopStatus == .bSet else { return }
      mpv.setDouble(MPVOption.PlaybackControl.abLoopB, max(PlayerCore.minLoopPointTime, newValue))
    }
  }

  var isABLoopActive: Bool {
    abLoopA != 0 && abLoopB != 0 && mpv.getString(MPVOption.PlaybackControl.abLoopCount) != "0"
  }

  let playerNumber: Int

  static var keyBindings: [String: KeyMapping] = [:]

  override init() {
    playerNumber = PlayerCore.playerCoreCounter
    backgroundQueue = DispatchQueue(label: "IINAPlayerCoreTask\(playerNumber)", qos: .background)
    playlistQueue = DispatchQueue(label: "IINAPlaylistTask\(playerNumber)", qos: .utility)
    thumbnailQueue = DispatchQueue(label: "IINAPlayerCoreThumbnailTask\(playerNumber)", qos: .utility)
    super.init()
    self.mpv = MPVController(playerCore: self)
    self.mainWindow = MainWindowController(playerCore: self)
    self.miniPlayer = MiniPlayerWindowController(playerCore: self)
    self.initialWindow = InitialWindowController(playerCore: self)
    self._touchBarSupport = TouchBarSupport(playerCore: self)
  }

  // MARK: - Plugins

  static func reloadPluginForAll(_ plugin: JavascriptPlugin) {
    playerCores.forEach { $0.reloadPlugin(plugin) }
    AppDelegate.shared.menuController?.updatePluginMenu()
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
    mainWindow.quickSettingView.updatePluginTabs()
  }

  // MARK: - Control

  private func open(_ url: URL?, shouldAutoLoad: Bool = false) {
    guard let url = url else {
      log("empty file path or url", level: .error)
      return
    }
    log("Open URL: \(url.absoluteString)")
    let isNetwork = !url.isFileURL
    if isNetwork {
      currentWindow?.close()
    }
    if shouldAutoLoad {
      info.shouldAutoLoadFiles = true
    }
    info.hdrEnabled = Preference.bool(for: .enableHdrSupport)
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

    // Handle folder URL (to support mpv shuffle, etc), BD folders and m3u / m3u8 files first.
    // For these cases, mpv will load/build the playlist and notify IINA when it can be retrieved.
    if urls.count == 1 {
      let url = urls[0]

      if isBDFolder(url)
          || Utility.playlistFileExt.contains(url.absoluteString.lowercasedPathExtension) {
        info.shouldAutoLoadFiles = false
        open(url)
        return nil
      }
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
      // For apps built with Xcode 15 or later the behavior of the URL initializer has changed when
      // running under macOS Sonoma or later. The behavior now matches URLComponents and will
      // automatically percent encode characters. Must not apply percent encoding to the string
      // passed to the URL initializer if the new new behavior is active.
      var performPercentEncoding = true
#if compiler(>=5.9)
      if #available(macOS 14, *) {
        performPercentEncoding = false
      }
#endif
      var pstr = str
      if performPercentEncoding {
        guard let encoded = str.addingPercentEncoding(withAllowedCharacters: .urlAllowed) else {
          log("Cannot add percent encoding for \(str)", level: .error)
          return
        }
        pstr = encoded
      }
      guard let url = URL(string: pstr) else {
        log("Cannot parse url for \(pstr)", level: .error)
        return
      }
      openURL(url)
    }
  }


  private func openMainWindow(path: String, url: URL, isNetwork: Bool) {
    log("Opening \(path) in main window")
    info.currentURL = url
    info.isNetworkResource = isNetwork
    if isNetwork {
      AppDelegate.shared.openURLWindow.showLoadingScreen(playerCore: self)
    }

    let _ = mainWindow.window
    mainWindow.pendingShow = true
    miniPlayer.pendingShow = true
    initialWindow.close()

    // Send load file command
    info.justOpenedFile = true
    info.state = .loading
    mpv.command(.loadfile, args: [path], level: .verbose)

    if Preference.bool(for: .autoRepeat) {
       let loopMode = Preference.DefaultRepeatMode(rawValue: Preference.integer(for: .defaultRepeatMode))
       setLoopMode(loopMode == .file ? .file : .playlist)
     }
  }

  static func loadKeyBindings() {
    Logger.log("Loading key bindings")
    let userConfigs = PrefKeyBindingViewController.userConfigs
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
    Logger.log("Set key bindings (\(keyMappings.count) mappings)")
    // If multiple bindings map to the same key, choose the last one
    var keyBindingsDict: [String: KeyMapping] = [:]
    var orderedKeyList: [String] = []
    keyMappings.forEach {
      if $0.rawKey == "default-bindings" && $0.action.count == 1 && $0.action[0] == "start" {
        Logger.log("Skipping line: \"default-bindings start\"", level: .verbose)
      } else if let kb = filterSectionBindings($0) {
        let key = kb.normalizedMpvKey
        if keyBindingsDict[key] == nil {
          orderedKeyList.append(key)
        }
        keyBindingsDict[key] = kb
      }
    }
    PlayerCore.keyBindings = keyBindingsDict

    // For menu item bindings, filter duplicate keys as above, but preserve order
    var kbUniqueOrderedList: [KeyMapping] = []
    for key in orderedKeyList {
      kbUniqueOrderedList.append(keyBindingsDict[key]!)
    }

    AppDelegate.shared.menuController.updateKeyEquivalentsFrom(kbUniqueOrderedList)

    NotificationCenter.default.post(Notification(name: .iinaGlobalKeyBindingsChanged, object: kbUniqueOrderedList))
  }

  static private func filterSectionBindings(_ kb: KeyMapping) -> KeyMapping? {
    guard let section = kb.section else {
      return kb
    }

    if section == "default" {
      // Drop "{default}" because it is unnecessary and will get in the way of libmpv command execution
      let newRawAction = Array(kb.action.dropFirst()).joined(separator: " ")
      return KeyMapping(rawKey: kb.rawKey, rawAction: newRawAction, isIINACommand: kb.isIINACommand, comment: kb.comment)
    } else {
      Logger.log("Skipping binding from section \"\(section)\": \(kb.rawKey)", level: .verbose)
      return nil
    }
  }

  func startMPV() {
    // set path for youtube-dl
    let oldPath = String(cString: getenv("PATH")!)
    var path = Utility.exeDirURL.path + ":" + oldPath
    if let customYtdlPath = Preference.string(for: .ytdlSearchPath), !customYtdlPath.isEmpty {
      path = customYtdlPath + ":" + path
    }
    setenv("PATH", path, 1)
    log("Set path to \(path)")

    // set http proxy
    if let proxy = Preference.string(for: .httpProxy), !proxy.isEmpty {
      setenv("http_proxy", "http://" + proxy, 1)
      log("Set http_proxy to \(proxy)")
    }

    mpv.mpvInit()
    events.emit(.mpvInitialized)

    if !getAudioDevices().contains(where: { $0["name"] == Preference.string(for: .audioDevice)! }) {
      setAudioDevice("auto")
    }
  }

  func initVideo() {
    // init mpv render context.
    mpv.mpvInitRendering()
    mainWindow.videoView.startDisplayLink()
  }

  // unload main window video view
  func uninitVideo() {
    guard mainWindow.loaded else { return }
    mainWindow.videoView.uninit()
  }

  private func savePlayerState() {
    savePlaybackPosition()
    refreshSyncUITimer()
  }

  /// Initiate shutdown of this player.
  ///
  /// This method is intended to only be used during application termination. Once shutdown has been initiated player methods
  /// **must not** be called.
  /// - Important: As a part of shutting down the player this method sends a quit command to mpv. Even though the command is
  ///     sent to mpv using the synchronous API mpv executes the quit command asynchronously. The player is not fully shutdown
  ///     until mpv finishes executing the quit command and shuts down.
  /// - Note: If the user clicks on `Quit` right after starting to play a video then the background task may still be running and
  ///     loading files into the playlist and adding subtitles. If that is the case then the background task **must be** stopped before
  ///     sending a `quit` command to mpv. If the background task is allowed to access mpv after a `quit` command has been
  ///     sent mpv could crash. The `stop` method takes care of instructing the background task to stop and will wait for it to stop
  ///     before sending a `stop` command to mpv. _However_ mpv will stop on its own if the end of the video is reached. When
  ///     that happens while IINA is quitting then this method may be called with the background task still running. If the background
  ///     task is still running this method only changes the player state. When the background task ends it will notice that shutting
  ///     down was in progress and will call this method again to continue the process of shutting down..
  func shutdown() {
    info.state = .shuttingDown
    guard !backgroundTaskInUse else { return }
    log("Shutting down")
    savePlayerState()
    mpv.mpvQuit()
  }

  /// Notify the task running in the background queue it should stop.
  ///
  /// The background queue will be instructed to stop by invalidating the ticket it owns. The background task polls the current ticket
  /// and eventually will notice it has changed and will abandon its work.
  private func stopBackgroundTask() {
    log("Stopping background task")
    $backgroundQueueTicket.withLock { $0 += 1 }
  }

  /// Respond to the mpv core shutting down.
  /// - Important: Normally shutdown of the mpv core occurs after IINA has sent a `quit` command to the mpv core and that
  ///     asynchronous command completes. _However_ this can also occur when the user uses mpv's IPC interface to send a quit
  ///     command directly to mpv. Accessing a mpv core after it has shutdown is not permitted by mpv and can trigger a crash.
  ///     When IINA is in control of the termination sequence it is able to prevent access to the mpv core. For example, observers are
  ///     removed before sending the `quit` command. But when shutdown is initiated by mpv the actions IINA takes before
  ///     shutting down mpv are bypassed. This means a mpv initiated shutdown can't be made fully deterministic as there are inherit
  ///     windows of vulnerability that can not be fully closed. IINA has no choice but to support a mpv initiated shutdown as best it
  ///     can.
  func mpvHasShutdown() {
    let isMPVInitiated = info.state != .shuttingDown
    let suffix = isMPVInitiated ? " (initiated by mpv)" : ""
    log("Player has shutdown\(suffix)")
    info.state = .shutDown
    if isMPVInitiated {
      // The user must have used mpv's IPC interface to send a quit command directly to mpv. Must
      // perform the actions that were skipped when IINA's normal shutdown process was bypassed.
      if backgroundTaskInUse {
        stopBackgroundTask()
      }
      mpv.removeObservers()
      savePlayerState()
    }
    uninitVideo()
    postNotification(.iinaPlayerShutdown)
    if isMPVInitiated {
      // Initiate application termination. AppKit requires this be done from the main thread,
      // however the main dispatch queue must not be used to avoid blocking the queue as per
      // instructions from Apple.
      RunLoop.main.perform(inModes: [.common]) {
        NSApp.terminate(nil)
      }
    }
  }

  /// Switch the current player to mini player from the main window.
  ///
  /// - Parameters:
  ///     - showMiniPlayer: set to false when this function is called when tracklist is changed.
  ///     In this case, wait for `MPV_EVENT_VIDEO_RECONFIG` to show the mini player.
  ///
  /// This function is called:
  /// 1) On `trackListChanged`, it will check the current media and settings to determine whether
  /// or not to switch to mini player automatically
  /// 2) On user initiated button actions
  ///
  func switchToMiniPlayer(automatically: Bool = false, showMiniPlayer: Bool = true) {
    log("Switch to mini player, automatically=\(automatically)")
    if !automatically {
      // Toggle manual override
      overrideAutoSwitchToMusicMode = !overrideAutoSwitchToMusicMode
      Logger.log("Changed overrideAutoSwitchToMusicMode to \(overrideAutoSwitchToMusicMode)",
                 level: .verbose, subsystem: subsystem)
    }

    // hide main window
    mainWindow.window?.orderOut(self)

    let needRestoreLayout = !miniPlayer.loaded
    let _ = miniPlayer.window

    miniPlayer.updateTitle()
    refreshSyncUITimer()
    let playlistView = mainWindow.playlistView.view
    let videoView = mainWindow.videoView
    // reset down shift for playlistView
    mainWindow.playlistView.downShift = 0
    // hide sidebar
    if mainWindow.sideBarStatus != .hidden {
      mainWindow.hideSideBar(animate: false)
    }

    // move playlist view
    playlistView.removeFromSuperview()
    mainWindow.playlistView.useCompactTabHeight = true
    miniPlayer.playlistWrapperView.addSubview(playlistView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": playlistView])
    // move video view
    videoView.removeFromSuperview()
    miniPlayer.videoWrapperView.addSubview(videoView, positioned: .below, relativeTo: nil)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": videoView])

    // if received video size before switching to music mode, hide default album art
    let width, height: Int
    if info.vid != 0 {
      miniPlayer.defaultAlbumArt.isHidden = true
      (width, height) = videoSizeForDisplay
    } else {
      (width, height) = (1, 1)
    }

    let aspect = CGFloat(width) / CGFloat(height)
    miniPlayer.updateVideoViewAspectConstraint(withAspect: aspect)
    miniPlayer.window?.layoutIfNeeded()

    // in case of video size changed, reset mini player window size if playlist is folded
    if !miniPlayer.isPlaylistVisible {
      miniPlayer.setToInitialWindowSize(display: true, animate: false)
    }

    isInMiniPlayer = true

    // restore layout
    if needRestoreLayout {
      if !Preference.bool(for: .musicModeShowAlbumArt) {
        miniPlayer.toggleVideoView(self)
        if let origin = miniPlayer.window?.frame.origin {
          miniPlayer.window?.setFrameOrigin(.init(x: origin.x, y: origin.y + miniPlayer.videoView.frame.height))
        }
      }
      if Preference.bool(for: .musicModeShowPlaylist) {
        miniPlayer.togglePlaylist(self)
      }
    }

    currentController.setupUI()
    miniPlayer.pendingShow = true
    if showMiniPlayer {
      notifyWindowVideoSizeChanged()
    }
    videoView.videoLayer.draw(forced: true)
    events.emit(.musicModeChanged, data: true)
  }

  /// Switch the current player to main player from the mini player.
  ///
  /// - Parameters:
  ///     - showMainWindow: set to false when this function is called when tracklist is changed.
  ///     In this case, wait for `MPV_EVENT_VIDEO_RECONFIG` to show the main window. Also set to false
  ///     when the mini player is closed.
  ///
  /// This function is called:
  /// 1) On `trackListChanged`, it will check the current media and settings to determine whether
  /// or not to switch to main window automatically
  /// 2) On user initiated button actions
  /// 3) When closing the mini player
  ///
  func switchBackFromMiniPlayer(automatically: Bool = false, showMainWindow: Bool = true) {
    log("Switch to normal window from mini player, automatically=\(automatically)")
    if !automatically {
      overrideAutoSwitchToMusicMode = !overrideAutoSwitchToMusicMode
      Logger.log("Changed overrideAutoSwitchToMusicMode to \(overrideAutoSwitchToMusicMode)",
                 level: .verbose, subsystem: subsystem)
    }
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

    // hide mini player
    miniPlayer.window?.orderOut(nil)
    isInMiniPlayer = false

    mainWindow.pendingShow = true
    if showMainWindow {
      currentController.setupUI()
      mainWindow.updateTitle()
      notifyWindowVideoSizeChanged()
    }
    mainWindow.videoView.videoLayer.draw(forced: true)
    events.emit(.musicModeChanged, data: false)
  }

  // MARK: - MPV commands

  func togglePause(_ set: Bool? = nil) {
    info.state == .paused ? resume() : pause()
  }

  /// Pause playback.
  ///
  /// - Important: Setting the `pause` property will cause `mpv` to emit a `MPV_EVENT_PROPERTY_CHANGE` event. The
  ///     event will still be emitted even if the `mpv` core is idle. If the setting `Pause when machine goes to sleep` is
  ///     enabled then `PlayerWindowController` will call this method in response to a
  ///     `NSWorkspace.willSleepNotification`. That happens even if the window is closed and the player is idle. In
  ///     response the event handler in `MPVController` will call `VideoView.displayIdle`. The suspicion is that calling this
  ///     method results in a call to `CVDisplayLinkCreateWithActiveCGDisplays` which fails because the display is
  ///     asleep. Thus `setFlag` **must not** be called if the `mpv` core is idle or stopping. See issue
  ///     [#4520](https://github.com/iina/iina/issues/4520)
  func pause() {
    guard info.state.active else { return }
    mpv.setFlag(MPVOption.PlaybackControl.pause, true, level: .verbose)
  }

  func resume() {
    // Restart playback when reached EOF
    if mpv.getFlag(MPVProperty.eofReached) {
      seek(absoluteSecond: 0)
    }
    mpv.setFlag(MPVOption.PlaybackControl.pause, false, level: .verbose)
  }

  /// Stop playback and unload the media.
  ///
  /// This method is called when a window closes. The player may be:
  /// - In one of the "active" states
  /// - In the `idle` state
  /// - In the `shutdown` state
  ///
  /// The player will be in one of the active states if the user closes the window or quits IINA while the video is playing or paused. If the
  /// end of the video is reached then the mpv core will go into the `idle` state. In this case the `stop` command must not be sent
  /// to mpv as the core is already stopped. The player will be in the `shutdown` state if quitting was initiated through mpv. When this
  /// happens the `mpvHasShutdown` method handles tasks required to stop the player. In this case this method has nothing to do.
  /// - Note: If playback is stopped right after starting to play the video then the background task may still be running and loading
  ///     files into the playlist and adding subtitles. If that is the case then the background task must be stopped before sending a
  ///     `stop` command to mpv. This happens asynchronously. This method will invalidate the ticket that the background task
  ///     periodically checks to get the task to end early. When the background task ends it will notice that stopping was in progress
  ///     and call this method again to continue the process of stopping. It is important to stop the background task as if it is still
  ///     running when the mpv core is shutdown it may call into mpv triggering a crash.
  func stop() {
    guard info.state != .shutDown else { return }
    savePlaybackPosition()

    // The player may already be stopped in which case the state must not be set to stopping.
    if info.state != .idle {
      // Setting of state must come after saving playback position or that method will not save the
      // watch later configuration.
      info.state = .stopping

      // Make sure playback is paused to free up machine resources when quitting.
      mpv.setFlag(MPVOption.PlaybackControl.pause, true, level: .verbose)
    }

    // Must first stop the background task if it is running.
    if backgroundTaskInUse {
      stopBackgroundTask()
      return
    }

    if info.state != .idle {
      log("Stopping playback")
    }
    mainWindow.videoView.stopDisplayLink()
    info.$matchedSubs.withLock { $0.removeAll() }

    // Refresh UI synchronization as it will detect the player is stopping and shutdown the timer.
    refreshSyncUITimer()

    // Do not send a stop command to mpv if it is already stopped.
    guard info.state != .idle else { return }
    mpv.command(.stop, level: .verbose)
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
    mpv.command(.seek, args: ["\(percent)", seekMode], checkError: false, level: .verbose)
  }

  func seek(relativeSecond: Double, option: Preference.SeekOption) {
    switch option {

    case .relative:
      mpv.command(.seek, args: ["\(relativeSecond)", "relative"], checkError: false, level: .verbose)

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
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // It must be running when stepping to avoid slowdowns caused by mpv waiting for IINA to call
    // mpv_render_report_swap.
    mainWindow.videoView.displayActive()
    if backwards {
      mpv.command(.frameBackStep)
    } else {
      mpv.command(.frameStep)
    }
  }

  /// Takes a screenshot, attempting to augment mpv's `screenshot` command with additional functionality & control, for example
  /// the ability to save to clipboard instead of or in addition to file, and displaying the screenshot's thumbnail via the OSD.
  /// Returns `true` if a command was sent to mpv; `false` if no command was sent.
  ///
  /// If the prefs for `Preference.Key.screenshotSaveToFile` and `Preference.Key.screenshotCopyToClipboard` are both `false`,
  /// this function does nothing and returns `false`.
  ///
  /// ## Determining screenshot flags
  /// If `keyBinding` is present, it should contain an mpv `screenshot` command. If its action includes any flags, they will be
  /// used. If `keyBinding` is not present or its command has no flags, the value for `Preference.Key.screenshotIncludeSubtitle` will
  /// be used to determine the flags:
  /// - If `true`, the command `screenshot subtitles` will be sent to mpv.
  /// - If `false`, the command `screenshot video` will be sent to mpv.
  ///
  /// Note: IINA overrides mpv's behavior in some ways:
  /// 1. As noted above, if the stored values for `Preference.Key.screenshotSaveToFile` and `Preference.Key.screenshotCopyToClipboard` are
  /// set to false, all screenshot commands will be ignored.
  /// 2. When no flags are given with `screenshot`: instead of defaulting to `subtitles` as mpv does, IINA will use the value for
  /// `Preference.Key.screenshotIncludeSubtitle` to decide between `subtitles` or `video`.
  @discardableResult
  func screenshot(fromKeyBinding keyBinding: KeyMapping? = nil) -> Bool {
    let saveToFile = Preference.bool(for: .screenshotSaveToFile)
    let saveToClipboard = Preference.bool(for: .screenshotCopyToClipboard)
    guard saveToFile || saveToClipboard else {
      log("Ignoring screenshot request: all forms of screenshots are disabled in prefs", level: .warning)
      return false
    }

    guard let vid = info.vid, vid > 0 else {
      log("Ignoring screenshot request: no video stream is being played", level: .warning)
      return false
    }

    log("Screenshot requested by user\(keyBinding == nil ? "" : " (rawAction: \(keyBinding!.rawAction))")")

    var commandFlags: [String] = []

    if let keyBinding {
      var canUseIINAScreenshot = true

      guard let commandName = keyBinding.action.first, commandName == MPVCommand.screenshot.rawValue else {
        log("Cannot take screenshot: unexpected first token in key binding action: \(keyBinding.rawAction)", level: .error)
        return false
      }
      if keyBinding.action.count > 1 {
        commandFlags = keyBinding.action[1].split(separator: "+").map{String($0)}

        for flag in commandFlags {
          switch flag {
          case "window", "subtitles", "video":
            // These are supported
            break
          case "each-frame":
            // Option is not currently supported by IINA's screenshot command
            canUseIINAScreenshot = false
          default:
            // Unexpected flag. Let mpv decide how to handle
            log("Unrecognized flag for mpv 'screenshot' command: '\(flag)'", level: .warning)
            canUseIINAScreenshot = false
          }
        }
      }

      if !canUseIINAScreenshot {
        let returnValue = mpv.command(rawString: keyBinding.rawAction)
        return returnValue == 0
      }
    }

    if commandFlags.isEmpty {
      let includeSubtitles = Preference.bool(for: .screenshotIncludeSubtitle)
      commandFlags.append(includeSubtitles ? "subtitles" : "video")
    }

    mpv.asyncCommand(.screenshot, args: commandFlags, replyUserdata: MPVController.UserData.screenshot)
    return true
  }

  /// Initializes and returns an image object with the contents of the specified URL.
  ///
  /// At this time, the normal [NSImage](https://developer.apple.com/documentation/appkit/nsimage/1519907-init)
  /// initializer will fail to create an image object if the image file was encoded in [JPEG XL](https://jpeg.org/jpegxl/) format.
  /// In older versions of macOS this will also occur if the image file was encoded in [WebP](https://en.wikipedia.org/wiki/WebP/)
  /// format. As these are supported formats for screenshots this method will fall back to using FFmpeg to create the `NSImage` if
  /// the normal initializer fails to return an object.
  /// - Parameter url: The URL identifying the image.
  /// - Returns: An initialized `NSImage` object or `nil` if the method cannot create an image representation from the contents
  ///       of the specified URL.
  private func createImage(_ url: URL) -> NSImage? {
    if let image = NSImage(contentsOf: url) {
      return image
    }
    // The following internal property was added to provide a way to disable the FFmpeg image
    // decoder should a problem be discovered by users running old versions of macOS.
    guard Preference.bool(for: .enableFFmpegImageDecoder) else { return nil }
    Logger.log("Using FFmpeg to decode screenshot: \(url)")
    return FFmpegController.createNSImage(withContentsOf: url)
  }

  func screenshotCallback() {
    let saveToFile = Preference.bool(for: .screenshotSaveToFile)
    let saveToClipboard = Preference.bool(for: .screenshotCopyToClipboard)
    guard saveToFile || saveToClipboard else { return }
    log("Screenshot done: saveToFile=\(saveToFile), saveToClipboard=\(saveToClipboard)", level: .verbose)

    guard let imageFolder = mpv.getString(MPVOption.Screenshot.screenshotDir) else { return }
    guard let lastScreenshotURL = Utility.getLatestScreenshot(from: imageFolder) else { return }
    guard let image = createImage(lastScreenshotURL) else {
      self.sendOSD(.screenshot)
      if !saveToFile {
        try? FileManager.default.removeItem(at: lastScreenshotURL)
      }
      return
    }
    if saveToClipboard {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([image])
    }
    guard Preference.bool(for: .screenshotShowPreview) else {
      self.sendOSD(.screenshot)
      if !saveToFile {
        try? FileManager.default.removeItem(at: lastScreenshotURL)
      }
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

  /// Invoke the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  ///
  /// The A-B loop command cycles mpv through these states:
  /// - Cleared (looping disabled)
  /// - A loop point set
  /// - B loop point set (looping enabled)
  ///
  /// When the command is first invoked it sets the A loop point to the timestamp of the current frame. When the command is invoked
  /// a second time it sets the B loop point to the timestamp of the current frame, activating looping and causing mpv to seek back to
  /// the A loop point. When the command is invoked again both loop points are cleared (set to zero) and looping stops.
  func abLoop() {
    // may subject to change
    mpv.command(.abLoop)
    syncAbLoop()
    sendOSD(.abLoop(info.abLoopStatus))
  }

  /// Synchronize IINA with the state of the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  func syncAbLoop() {
    // Obtain the values of the ab-loop-a and ab-loop-b options representing the A & B loop points.
    let a = abLoopA
    let b = abLoopB
    if a == 0 {
      if b == 0 {
        // Neither point is set, the feature is disabled.
        info.abLoopStatus = .cleared
      } else {
        // The B loop point is set without the A loop point having been set. This is allowed by mpv
        // but IINA is not supposed to allow mpv to get into this state, so something has gone
        // wrong. This is an internal error. Log it and pretend that just the A loop point is set.
        log("Unexpected A-B loop state, ab-loop-a is \(a) ab-loop-b is \(b)", level: .error)
        info.abLoopStatus = .aSet
      }
    } else {
      // A loop point has been set. B loop point must be set as well to activate looping.
      info.abLoopStatus = b == 0 ? .aSet : .bSet
    }
    // The play slider has knobs representing the loop points, make insure the slider is in sync.
    mainWindow?.syncSlider()
    log("Synchronized info.abLoopStatus \(info.abLoopStatus)")
  }

  func togglePlaylistLoop() {
    let loopMode = getLoopMode()
    if loopMode == .playlist {
      setLoopMode(.off)
    } else {
      setLoopMode(.playlist)
    }
  }

  func toggleFileLoop() {
    let loopMode = getLoopMode()
    if loopMode == .file {
      setLoopMode(.off)
    } else {
      setLoopMode(.file)
    }
  }

  func getLoopMode() -> LoopMode {
    let loopFileStatus = mpv.getString(MPVOption.PlaybackControl.loopFile)
    guard loopFileStatus != "inf" else { return .file }
    if let loopFileStatus = loopFileStatus, let count = Int(loopFileStatus), count != 0 {
      return .file
    }
    let loopPlaylistStatus = mpv.getString(MPVOption.PlaybackControl.loopPlaylist)
    guard loopPlaylistStatus != "inf", loopPlaylistStatus != "force" else { return .playlist }
    guard let loopPlaylistStatus = loopPlaylistStatus, let count = Int(loopPlaylistStatus) else {
      return .off
    }
    return count == 0 ? .off : .playlist
  }

  func setLoopMode(_ newMode: LoopMode) {
    switch newMode {
    case .playlist:
      mpv.setString(MPVOption.PlaybackControl.loopPlaylist, "inf")
      mpv.setString(MPVOption.PlaybackControl.loopFile, "no")
    case .file:
      mpv.setString(MPVOption.PlaybackControl.loopFile, "inf")
    case .off:
      mpv.setString(MPVOption.PlaybackControl.loopPlaylist, "no")
      mpv.setString(MPVOption.PlaybackControl.loopFile, "no")
    }
  }

  func nextLoopMode() {
    setLoopMode(getLoopMode().next())
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
    mpv.setDouble(MPVOption.Audio.volume, appliedVolume, level: .verbose)
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

  func setSpeed(_ speed: Double) {
    let speed = speed < AppData.mpvMinPlaybackSpeed ? AppData.mpvMinPlaybackSpeed : speed
    mpv.setDouble(MPVOption.PlaybackControl.speed, speed)
  }

  func setVideoAspect(_ aspect: String) {
    if Regex.aspect.matches(aspect) {
      mpv.setString(MPVOption.Video.videoAspectOverride, aspect)
      info.unsureAspect = aspect
    } else {
      mpv.setString(MPVOption.Video.videoAspectOverride, "-1")
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
    mpv.command(.set, args: [optionName, value.description], level: .verbose)
  }

  func loadExternalVideoFile(_ url: URL) {
    mpv.command(.videoAdd, args: [url.path], checkError: false) { code in
      if code < 0 {
        self.log("Unsupported video: \(url.path)", level: .error)
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_audio")
        }
      }
    }
  }

  func loadExternalAudioFile(_ url: URL) {
    mpv.command(.audioAdd, args: [url.path], checkError: false) { code in
      if code < 0 {
        self.log("Unsupported audio: \(url.path)", level: .error)
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_audio")
        }
      }
    }
  }

  func toggleSubVisibility(_ set: Bool? = nil) {
    let newState = set ?? !info.isSubVisible
    mpv.setFlag(MPVOption.Subtitles.subVisibility, newState)
  }

  func toggleSecondSubVisibility(_ set: Bool? = nil) {
    let newState = set ?? !info.isSecondSubVisible
    mpv.setFlag(MPVOption.Subtitles.secondarySubVisibility, newState)
  }

  func loadExternalSubFile(_ url: URL, delay: Bool = false) {
    var track: MPVTrack?
    info.$subTracks.withLock { track = $0.first(where: { $0.externalFilename == url.path }) }
    if let track = track {
      mpv.command(.subReload, args: [String(track.id)], checkError: false)
      return
    }

    mpv.command(.subAdd, args: [url.path], checkError: false, level: .verbose) { code in
      if code < 0 {
        self.log("Unsupported sub: \(url.path)", level: .error)
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
    info.$subTracks.withLock {
      for subTrack in $0 {
        mpv.command(.subReload, args: ["\(subTrack.id)"], checkError: false) { code in
          if code < 0 {
            self.log("Failed reloading subtitles: error code \(code)", level: .error)
          }
        }
      }
    }
    getTrackInfo()
    info.$subTracks.withLock {
      if let currentSub = $0.first(where: {$0.externalFilename == currentSubName}) {
        setTrack(currentSub.id, forType: .sub)
      }
    }
    mainWindow?.quickSettingView.reload()
  }

  func setAudioDelay(_ delay: Double) {
    mpv.setDouble(MPVOption.Audio.audioDelay, delay)
  }

  func setSubDelay(_ delay: Double, forPrimary: Bool = true) {
    let option = forPrimary ? MPVOption.Subtitles.subDelay : MPVOption.Subtitles.secondarySubDelay
    mpv.setDouble(option, delay)
  }

  private func _addToPlaylist(_ path: String) {
    mpv.command(.loadfile, args: [path, "append"], level: .verbose)
  }

  func addToPlaylist(_ path: String, silent: Bool = false) {
    _addToPlaylist(path)
    if !silent {
      postNotification(.iinaPlaylistChanged)
    }
  }

  private func _playlistMove(_ from: Int, to: Int) {
    mpv.command(.playlistMove, args: ["\(from)", "\(to)"], level: .verbose)
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
    let previousCount = info.$playlist.withLock { $0.count }
    if index <= previousCount && index >= 0 {
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
    guard !indexSet.isEmpty else { return }
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

  func playFileInPlaylist(_ pos: Int) {
    mpv.setInt(MPVProperty.playlistPos, pos)
    getPlaylist()
  }

  func navigateInPlaylist(nextMedia: Bool) {
    mpv.command(nextMedia ? .playlistNext : .playlistPrev, checkError: false)
  }

  @discardableResult
  func playChapter(_ pos: Int) -> MPVChapter? {
    log("Seeking to chapter \(pos)", level: .verbose)
    let chapters = info.chapters
    guard pos < chapters.count else {
      return nil
    }
    let chapter = chapters[pos]
    mpv.command(.seek, args: ["\(chapter.time.second)", "absolute"])
    resume()
    // need to update time pos
    syncUITime()
    return chapter
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
    let freqList = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    let paramString = freqList.enumerated().map { (index, freq) in
      "equalizer=f=\(freq):t=h:width=\(Double(freq) / 1.224744871):g=\(gains[index])"
    }.joined(separator: ",")
    let filter = MPVFilter(name: "lavfi", label: Constants.FilterName.audioEq, paramString: "[\(paramString)]")
    addAudioFilter(filter)
    info.audioEqFilter = filter
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
    log("Adding video filter \(filter)...")
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
    if !result {
      log("Failed to add video filter \(filter)", level: .warning)
    } else {
      log("Successfully added video filter \(filter)")
    }
    return result
  }

  private func logRemoveFilter(type: String, result: Bool, name: String) {
    if !result {
      log("Failed to remove \(type) filter \(name)", level: .warning)
    } else {
      log("Successfully removed \(type) filter \(name)")
    }
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
    log("Removing video filter \(filter)...")
    let result = mpv.removeFilter(MPVProperty.vf, index)
    logRemoveFilter(type: "video", result: result, name: filter)
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
    log("Removing video filter \(filter)...")
    var result = true
    mpv.command(.vf, args: ["remove", filter], checkError: false) { result = $0 >= 0 }
    logRemoveFilter(type: "video", result: result, name: filter)
    return result
  }

  /// Add an audio filter given as a `MPVFilter` object.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  @discardableResult
  func addAudioFilter(_ filter: MPVFilter) -> Bool { addAudioFilter(filter.stringFormat) }

  /// Add an audio filter given as a string.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  @discardableResult
  func addAudioFilter(_ filter: String) -> Bool {
    log("Adding audio filter \(filter)...")
    var result = true
    mpv.command(.af, args: ["add", filter], checkError: false) { result = $0 >= 0 }
    if !result {
      log("Failed to add audio filter \(filter)", level: .warning)
    } else {
      log("Successfully added audio filter \(filter)")
    }
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
    log("Removing audio filter \(filter)...")
    let result = mpv.removeFilter(MPVProperty.af, index)
    logRemoveFilter(type: "audio", result: result, name: filter)
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
  @discardableResult
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
  @discardableResult
  func removeAudioFilter(_ filter: String) -> Bool {
    log("Removing audio filter \(filter)...")
    var result = true
    mpv.command(.af, args: ["remove", filter], checkError: false)  { result = $0 >= 0 }
    logRemoveFilter(type: "audio", result: result, name: filter)
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
      mpv.setDouble(MPVOption.Subtitles.subScale, scale, level: .verbose)
    } else {
      mpv.setDouble(MPVOption.Subtitles.subScale, -scale, level: .verbose)
    }
  }

  func setSubPos(_ pos: Int, forPrimary: Bool = true) {
    let option = forPrimary ? MPVOption.Subtitles.subPos : MPVOption.Subtitles.secondarySubPos
    mpv.setInt(option, pos, level: .verbose)
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

  func savePlaybackPosition() {
    guard Preference.bool(for: .resumeLastPosition) else { return }

    // The player must be active to be able to save the watch later configuration.
    if info.state.active {
      log("Write watch later config")
      mpv.command(.writeWatchLaterConfig, level: .verbose)
    }
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

  /// Uses an mpv `on_before_start_file` hook to honor mpv's `shuffle` command via IINA CLI.
  ///
  /// There is currently no way to remove an mpv hook once it has been added, so to minimize potential impact and/or side effects
  /// when not in use:
  /// 1. Only add the mpv hook if `--mpv-shuffle` (or equivalent) is specified. Because this decision only happens at launch,
  /// there is no risk of adding the hook more than once per player.
  /// 2. Use `shufflePending` to decide if it needs to run again. Set to `false` after use, and check its value as early as possible.
  func addShufflePlaylistHook() {
    $shufflePending.withLock{ $0 = true }

    func callback(next: @escaping () -> Void) {
      var mustShuffle = false
      $shufflePending.withLock{ shufflePending in
        if shufflePending {
          mustShuffle = true
          shufflePending = false
        }
      }

      guard mustShuffle else {
        log("Triggered on_before_start_file hook, but no shuffle needed", level: .verbose)
        next()
        return
      }

      DispatchQueue.main.async { [self] in
        log("Running on_before_start_file hook: shuffling playlist")
        mpv.command(.playlistShuffle)
        /// will cancel this file load sequence (so `fileLoaded` will not be called), then will start loading item at index 0
        mpv.command(.playlistPlayIndex, args: ["0"])
        next()
      }
    }

    mpv.addHook(MPVHook.onBeforeStartFile, hook: MPVHookValue(withBlock: callback))
  }

  // MARK: - Listeners

  // IMPORTANT!
  // The listener methods expect to be called from MPVController on the main thread. Much of the
  // data used by these methods is read by the UI using the main thread. Standardizing on using the
  // main thread avoids thread data races without the need for locks. Also a few of the methods call
  // AppKit methods that require use of the main thread.

  /// A [MPV_EVENT_START_FILE](https://mpv.io/manual/stable/#command-interface-mpv-event-start-file)
  /// was received.
  /// - Important: The event may be received after IINA has started to stop and shutdown the core. The event must be ignored if
  ///         the player is no longer active.
  func fileStarted(path: String) {
    guard info.state.active else { return }
    log("File started")
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

    if RemoteCommandController.useSystemMediaControl {
      NowPlayingInfoManager.updateInfo(state: .playing, withTitle: true)
    }

    // Auto load
    $backgroundQueueTicket.withLock { $0 += 1 }
    let shouldAutoLoadFiles = info.shouldAutoLoadFiles
    let currentTicket = backgroundQueueTicket
    backgroundTaskInUse = true
    backgroundQueue.async { [self] in
      do {
        // add files in same folder
        if shouldAutoLoadFiles {
          log("Started auto load")
          try autoLoadFilesInCurrentFolder(ticket: currentTicket)
        }
        // auto load matched subtitles
        if let matchedSubs = self.info.getMatchedSubs(path) {
          log("Found \(matchedSubs.count) subs for current file")
          for sub in matchedSubs {
            try checkTicket(currentTicket)
            loadExternalSubFile(sub)
          }
          // set sub to the first one
          try checkTicket(currentTicket)
          setTrack(1, forType: .sub)
        }
        autoSearchOnlineSub()
      } catch TicketExpiredError.ticketExpired {
        log("Background task stopping due to ticket expiration")
      } catch let err {
        log("Background task stopping due to error \(err.localizedDescription)", level: .error)
      }
      // This code must be queued to the main thread to avoid thread data races.
      DispatchQueue.main.async { [self] in
        backgroundTaskInUse = false
        log("Background task has stopped")
        // If the player is stopping then that process has been waiting for this background task to
        // finish. Call stop again to continue with the process of stopping this player. Stop must
        // also be called if mpv itself stopped the core (idle state). If IINA is quitting then the
        // shutdown process has been waiting for the task to end and shutdown must be called to
        // continue the process.
        if info.state == .stopping || info.state == .idle {
          stop()
        } else if info.state == .shuttingDown {
          shutdown()
        }
      }
    }
    events.emit(.fileStarted)
  }

  /// A [MPV_EVENT_FILE_LOADED](https://mpv.io/manual/stable/#command-interface-mpv-event-file-loaded)
  /// was received.
  ///
  /// This function is called right after the file is loaded. Should load all meta info here.
  /// - Important: The event may be received after IINA has started to stop and shutdown the core. The event must be ignored if
  ///         the player is no longer active.
  func fileLoaded() {
    guard info.state.active else { return }
    log("File loaded")
    info.state = .paused
    mpv.setFlag(MPVOption.PlaybackControl.pause, true, level: .verbose)
    // Get video size and set the initial window size
    let width = mpv.getInt(MPVProperty.width)
    let height = mpv.getInt(MPVProperty.height)
    let duration = mpv.getDouble(MPVProperty.duration)
    let pos = mpv.getDouble(MPVProperty.timePos)
    info.videoHeight = height
    info.videoWidth = width
    info.displayWidth = 0
    info.displayHeight = 0
    info.videoDuration = VideoTime(duration)
    if let filename = mpv.getString(MPVProperty.path) {
      info.setCachedVideoDuration(filename, duration)
    }
    info.videoPosition = VideoTime(pos)
    triedUsingExactSeekForCurrentFile = false
    checkUnsyncedWindowOptions()
    // generate thumbnails if window has loaded video
    if mainWindow.isVideoLoaded {
      generateThumbnails()
    }
    // call `trackListChanged` to load tracks and check whether need to switch to music mode
    trackListChanged()
    getPlaylist()
    getChapters()
    syncAbLoop()
    refreshSyncUITimer()
    touchBarSupport.setupTouchBarUI()

    if info.aid == 0 {
      mainWindow.muteButton.isEnabled = false
      mainWindow.volumeSlider.isEnabled = false
    }

    if info.vid == 0 {
      notifyWindowVideoSizeChanged()
    }

    if self.isInMiniPlayer {
      miniPlayer.defaultAlbumArt.isHidden = self.info.vid != 0
    }
    if Preference.bool(for: .fullScreenWhenOpen) && !mainWindow.fsState.isFullscreen && !isInMiniPlayer {
      mainWindow.toggleWindowFullScreen()
    }
    // add to history
    if let url = info.currentURL {
      let duration = info.videoDuration ?? .zero
      HistoryController.shared.add(url, duration: duration.second)
      if Preference.bool(for: .recordRecentFiles) && Preference.bool(for: .trackAllFilesInRecentOpenMenu) {
        AppDelegate.shared.noteNewRecentDocumentURL(url)
      }
    }
    postNotification(.iinaFileLoaded)
    events.emit(.fileLoaded, data: info.currentURL?.absoluteString ?? "")
    if !(info.justOpenedFile && Preference.bool(for: .pauseWhenOpen)) {
      mpv.setFlag(MPVOption.PlaybackControl.pause, false, level: .verbose)
    }
    syncUI(.playlist)
  }

  func fileEnded(dueToStopCommand: Bool) {
    // if receive end-file when loading file, might be error
    // wait for idle
    if info.state == .starting {
      if !dueToStopCommand {
        receivedEndFileWhileLoading = true
      }
    } else {
      info.shouldAutoLoadFiles = false
    }
  }

  func afChanged() {
    guard info.state.active else { return }
    postNotification(.iinaAFChanged)
  }

  func aidChanged() {
    guard info.state.active else { return }
    info.aid = Int(mpv.getInt(MPVOption.TrackSelection.aid))
    guard mainWindow.loaded else { return }
    mainWindow?.muteButton.isEnabled = (info.aid != 0)
    mainWindow?.volumeSlider.isEnabled = (info.aid != 0)
    postNotification(.iinaAIDChanged)
    sendOSD(.track(info.currentTrack(.audio) ?? .noneAudioTrack))
  }

  func chapterChanged() {
    guard info.state.active else { return }
    info.chapter = Int(mpv.getInt(MPVProperty.chapter))
    syncUI(.time)
    syncUI(.chapterList)
    postNotification(.iinaMediaTitleChanged)
  }

  func fullscreenChanged() {
    guard mainWindow.loaded, info.state.active else { return }
    let fs = mpv.getFlag(MPVOption.Window.fullscreen)
    if fs != mainWindow.fsState.isFullscreen {
      mainWindow.toggleWindowFullScreen()
    }
  }

  func idleActiveChanged() {
    if receivedEndFileWhileLoading && info.state == .starting {
      DispatchQueue.main.async { [unowned self] in
        currentController.close()
        if AppDelegate.shared.openURLWindow.window?.isVisible == true {
          AppDelegate.shared.openURLWindow.failedToLoadURL()
        } else {
          Utility.showAlert("error_open")
        }
      }
      info.currentURL = nil
      info.isNetworkResource = false
    }
    receivedEndFileWhileLoading = false
    if info.state.loaded {
      DispatchQueue.main.async {
        self.currentController.close()
      }
    }
    if info.state != .loading {
      log("Playback has stopped")
      info.state = .idle
      postNotification(.iinaPlayerStopped)
    }
  }

  func mediaTitleChanged() {
    guard info.state.active else { return }
    postNotification(.iinaMediaTitleChanged)
  }

  func needReloadQuickSettingsView() {
    guard info.state.active else { return }
    mainWindow.quickSettingView.reload()
  }

  func ontopChanged() {
    guard mainWindow.loaded, info.state.active else { return }
    let ontop = mpv.getFlag(MPVOption.Window.ontop)
    if ontop != mainWindow.isOntop {
      mainWindow.setWindowFloatingOnTop(ontop)
    }
  }

  func playbackRestarted() {
    log("Playback restarted")
    reloadSavedIINAfilters()
    mainWindow.videoView.videoLayer.draw(forced: true)

    if RemoteCommandController.useSystemMediaControl {
      NowPlayingInfoManager.updateInfo()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.info.disableOSDForFileLoading = false }
  }

  func refreshEdrMode() {
    guard mainWindow.loaded else { return }
    // No need to refresh if playback is being stopped. Must not attempt to refresh if mpv is
    // terminating as accessing mpv once shutdown has been initiated can trigger a crash.
    guard info.state.active else { return }
    mainWindow.videoView.refreshEdrMode()
  }

  func secondarySubDelayChanged(_ delay: Double) {
    sendOSD(.secondSubDelay(delay))
    needReloadQuickSettingsView()
  }

  func secondarySubPosChanged(_ position: Double) {
    sendOSD(.secondSubPos(position))
    needReloadQuickSettingsView()
  }

  func secondarySidChanged() {
    guard info.state.active else { return }
    info.secondSid = Int(mpv.getInt(MPVOption.Subtitles.secondarySid))
    postNotification(.iinaSIDChanged)
    sendOSD(.track(info.currentTrack(.secondSub) ?? .noneSubTrack))
  }

  func secondSubVisibilityChanged(_ visible: Bool) {
    guard info.isSecondSubVisible != visible else { return }
    info.isSecondSubVisible = visible
    sendOSD(visible ? .secondSubVisible : .secondSubHidden)
    postNotification(.iinaSecondSubVisibilityChanged)
  }

  func sidChanged() {
    guard info.state.active else { return }
    info.sid = Int(mpv.getInt(MPVOption.TrackSelection.sid))
    postNotification(.iinaSIDChanged)
    sendOSD(.track(info.currentTrack(.sub) ?? .noneSubTrack))
  }

  func subDelayChanged(_ delay: Double) {
    info.subDelay = delay
    sendOSD(.subDelay(delay))
    needReloadQuickSettingsView()
  }

  func subPosChanged(_ position: Double) {
    sendOSD(.subPos(position))
    needReloadQuickSettingsView()
  }

  func subVisibilityChanged(_ visible: Bool) {
    guard info.isSubVisible != visible else { return }
    info.isSubVisible = visible
    sendOSD(visible ? .subVisible : .subHidden)
    postNotification(.iinaSubVisibilityChanged)
  }

  func trackListChanged() {
    // No need to process track list changes if playback is being stopped. Must not process track
    // list changes if mpv is terminating as accessing mpv once shutdown has been initiated can
    // trigger a crash.
    guard info.state.active else { return }
    log("Track list changed")
    getTrackInfo()
    getSelectedTracks()
    let audioStatus = checkCurrentMediaIsAudio()
    currentMediaIsAudio = audioStatus

    // if need to switch to music mode
    if Preference.bool(for: .autoSwitchToMusicMode) {
      if overrideAutoSwitchToMusicMode {
        log("Skipping music mode auto-switch because overrideAutoSwitchToMusicMode is true", level: .verbose)
      } else if audioStatus == .isAudio && !isInMiniPlayer && !mainWindow.fsState.isFullscreen {
        log("Current media is audio: auto-switching to mini player")
        switchToMiniPlayer(automatically: true, showMiniPlayer: false)
      } else if audioStatus == .notAudio && isInMiniPlayer {
        log("Current media is not audio: auto-switching to normal window")
        switchBackFromMiniPlayer(automatically: true, showMainWindow: false)
      }
    }
    postNotification(.iinaTracklistChanged)
  }

  func onVideoReconfig() {
    // If loading file, video reconfig can return 0 width and height
    guard info.state.loaded else { return }
    var dwidth = mpv.getInt(MPVProperty.dwidth)
    var dheight = mpv.getInt(MPVProperty.dheight)
    if info.rotation == 90 || info.rotation == 270 {
      swap(&dwidth, &dheight)
    }
    if dwidth != info.displayWidth! || dheight != info.displayHeight! {
      // filter the last video-reconfig event before quit
      if dwidth == 0 && dheight == 0 && mpv.getFlag(MPVProperty.coreIdle) { return }
      // video size changed
      info.displayWidth = dwidth
      info.displayHeight = dheight
      notifyWindowVideoSizeChanged()
    }
  }

  func vfChanged() {
    guard info.state.active else { return }
    postNotification(.iinaVFChanged)
  }

  func vidChanged() {
    guard info.state.active else { return }
    info.vid = Int(mpv.getInt(MPVOption.TrackSelection.vid))
    postNotification(.iinaVIDChanged)
    sendOSD(.track(info.currentTrack(.video) ?? .noneVideoTrack))
  }

  func windowScaleChanged() {
    guard mainWindow.loaded, info.state.active else { return }
    let windowScale = mpv.getDouble(MPVOption.Window.windowScale)
    if fabs(windowScale - info.cachedWindowScale) > 10e-10 {
      mainWindow.setWindowScale(windowScale)
    }
  }

  private func autoSearchOnlineSub() {
    Thread.sleep(forTimeInterval: 0.5)
    if Preference.bool(for: .autoSearchOnlineSub) && !info.isNetworkResource &&
      (info.videoDuration?.second ?? 0.0) >= Preference.double(for: .autoSearchThreshold) * 60 {
      info.$subTracks.withLock {
        if $0.isEmpty {
          DispatchQueue.main.async {
            self.mainWindow.menuActionHandler.menuFindOnlineSub(.dummy)
          }
        }
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
  private func autoLoadFilesInCurrentFolder(ticket: Int) throws {
    try AutoFileMatcher(player: self, ticket: ticket).startMatching()
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

  /// Call this when `syncUITimer` may need to be started, stopped, or needs its interval changed. It will figure out the correct action.
  /// Just need to make sure that any state variables (e.g., `info.isPaused`, `isInMiniPlayer`,  etc.) are set *before* calling this method,
  /// not after, so that it makes the correct decisions.
  func refreshSyncUITimer() {
    // Check if timer should start/restart

    let useTimer: Bool
    if !info.state.active {
      useTimer = false
    } else if info.state == .paused {
      // Follow energy efficiency best practices and ensure IINA is absolutely idle when the
      // video is paused to avoid wasting energy with needless processing. If paused shutdown
      // the timer that synchronizes the UI and the high priority display link thread.
      useTimer = false
    } else if needsTouchBar || isInMiniPlayer {
      // Follow energy efficiency best practices and stop the timer that updates the OSC while it is
      // hidden. However the timer can't be stopped if the mini player is being used as it always
      // displays the OSC or the timer is also updating the information being displayed in the
      // touch bar. Does this host have a touch bar? Is the touch bar configured to show app controls?
      // Is the touch bar awake? Is the host being operated in closed clamshell mode? This is the kind
      // of information needed to avoid running the timer and updating controls that are not visible.
      // Unfortunately in the documentation for NSTouchBar Apple indicates "There’s no need, and no
      // API, for your app to know whether or not there’s a Touch Bar available". So this code keys
      // off whether AppKit has requested that a NSTouchBar object be created. This avoids running the
      // timer on Macs that do not have a touch bar. It also may avoid running the timer when a
      // MacBook with a touch bar is being operated in closed clameshell mode.
      useTimer = true
    } else if info.isNetworkResource {
      // May need to show, hide, or update buffering indicator at any time
      useTimer = true
    } else {
      // Need if fadeable views or OSD are visible
      useTimer = mainWindow.isUITimerNeeded()
    }

    let timeInterval = TimeInterval(DurationDisplayTextField.precision >= 2 ? AppData.syncTimePreciseInterval : AppData.syncTimeInterval)

    /// Invalidate existing timer:
    /// - if no longer needed
    /// - if still needed but need to change the `timeInterval`
    var wasTimerRunning = false
    if let existingTimer = self.syncUITimer, existingTimer.isValid {
      if useTimer && timeInterval == existingTimer.timeInterval {
        /// Don't restart the existing timer if not needed, because restarting will ignore any time it has
        /// already spent waiting, and could in theory result in a small visual jump (more so for long intervals).

        // Uncomment for debugging (too many calls)
//        Logger.log("SyncUITimer already running, no change needed", level: .verbose, subsystem: subsystem)
        return
      } else {
        wasTimerRunning = true
        existingTimer.invalidate()
        self.syncUITimer = nil
      }
    }

    if Logger.enabled && Logger.Level.preferred >= .verbose {
      var summary = wasTimerRunning ? (useTimer ? "restarting" : "didStop") : (useTimer ? "starting" : "notNeeded")
      if summary != "notNeeded" {  // too many calls; try not to flood the log
        if useTimer {
          summary += ", timeInterval \(timeInterval)"
        }
        Logger.log("SyncUITimer \(summary). Player={state:\(info.state) network:\(info.isNetworkResource) mini:\(isInMiniPlayer) touchBar:\(needsTouchBar)}",
                   level: .verbose, subsystem: subsystem)
      }
    }

    guard useTimer else { return }

    // Timer will start

    if !wasTimerRunning {
      // Do not wait for first redraw
      syncUITime()
    }

    syncUITimer = Timer.scheduledTimer(
      timeInterval: timeInterval,
      target: self,
      selector: #selector(self.syncUITime),
      userInfo: nil,
      repeats: true
    )
  }

  func notifyWindowVideoSizeChanged() {
    currentController.handleVideoSizeChange()
    if currentController.pendingShow {
      currentController.pendingShow = false
      currentController.showWindow(self)
      AppDelegate.shared.openURLWindow.close()
    }
  }

  // difficult to use option set
  enum SyncUIOption {
    case time
    case playButton
    case volume
    case chapterList
    case playlist
    case loop
  }

  @objc func syncUITime() {
    syncUI(.time)
  }
  
  func syncUI(_ options: [SyncUIOption]) {
    for option in options {
      syncUI(option)
    }
  }

  func syncUI(_ option: SyncUIOption) {
    // If window is not loaded or stopping or shutting down, ignore.
    guard mainWindow.loaded, info.state.active else { return }
    // This is too noisy and making verbose logs unreadable. Please uncomment when debugging syncing related issues.
    // log("Syncing UI \(option)", level: .verbose)

    switch option {

    case .time:
      let isNetworkStream = info.isNetworkResource
      if isNetworkStream {
        info.videoDuration?.second = mpv.getDouble(MPVProperty.duration)
      }
      // When the end of a video file is reached mpv does not update the value of the property
      // time-pos, leaving it reflecting the position of the last frame of the video. This is
      // especially noticeable if the onscreen controller time labels are configured to show
      // milliseconds. Adjust the position if the end of the file has been reached.
      let eofReached = mpv.getFlag(MPVProperty.eofReached)
      if eofReached, let duration = info.videoDuration?.second {
        info.videoPosition?.second = duration
      } else {
        info.videoPosition?.second = mpv.getDouble(MPVProperty.timePos)
      }
      info.constrainVideoPosition()
      if isNetworkStream {
        // Update cache info
        info.pausedForCache = mpv.getFlag(MPVProperty.pausedForCache)
        info.cacheUsed = ((mpv.getNode(MPVProperty.demuxerCacheState) as? [String: Any])?["fw-bytes"] as? Int) ?? 0
        info.cacheSpeed = mpv.getInt(MPVProperty.cacheSpeed)
        info.cacheTime = mpv.getInt(MPVProperty.demuxerCacheTime)
        info.bufferingState = mpv.getInt(MPVProperty.cacheBufferingState)
      }
      DispatchQueue.main.async { [self] in
        currentController.updatePlayTime(withDuration: isNetworkStream, andProgressBar: true)
        if !self.isInMiniPlayer && mainWindow.fsState.isFullscreen && mainWindow.displayTimeAndBatteryInFullScreen && !mainWindow.additionalInfoView.isHidden {
          self.mainWindow.updateAdditionalInfo()
        }
        if isNetworkStream {
          self.mainWindow.updateNetworkState()
        }
      }

    case .playButton:
      DispatchQueue.main.async {
        self.currentController.updatePlayButtonState(self.info.state == .paused ? .off : .on)
        self.touchBarSupport.updateTouchBarPlayBtn()
      }

    case .volume:
      DispatchQueue.main.async {
        self.currentController.updateVolume()
      }

    case .chapterList:
      DispatchQueue.main.async {
        // this should avoid sending reload when table view is not ready
        if self.isInMiniPlayer ? self.miniPlayer.isPlaylistVisible : self.mainWindow.sideBarStatus == .playlist {
          self.log("Syncing UI: chapterList")
          self.mainWindow.playlistView.chapterTableView.reloadData()
        }
      }

    case .playlist:
      DispatchQueue.main.async {
        if self.isPlaylistVisible {
          self.mainWindow.playlistView.playlistTableView.reloadData()
        }
      }

    case .loop:
      DispatchQueue.main.async {
        self.mainWindow.playlistView.updateLoopBtnStatus()
      }
    }
  }

  func sendOSD(_ osd: OSDMessage, autoHide: Bool = true, forcedTimeout: Float? = nil, accessoryView: NSView? = nil, context: Any? = nil, external: Bool = false) {
    // querying `mainWindow.isWindowLoaded` will initialize mainWindow unexpectedly
    guard mainWindow.loaded, info.state.active,
          Preference.bool(for: .enableOSD) || osd.alwaysEnabled, !osd.isDisabled else { return }
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

  func generateThumbnails() {
    log("Getting thumbnails")
    info.thumbnailsReady = false
    info.$thumbnails.withLock { $0.removeAll(keepingCapacity: true) }
    info.thumbnailsProgress = 0
    DispatchQueue.main.async {
      self.touchBarSupport.touchBarPlaySlider?.resetCachedThumbnails()
    }
    guard !info.isNetworkResource, let url = info.currentURL else {
      log("...stopped because cannot get file path", level: .warning)
      return
    }
    if !Preference.bool(for: .enableThumbnailForRemoteFiles) {
      if let attrs = try? url.resourceValues(forKeys: Set([.volumeIsLocalKey])), !attrs.volumeIsLocal! {
        log("...stopped because file is on a mounted remote drive", level: .warning)
        return
      }
    }
    if Preference.bool(for: .enableThumbnailPreview) {
      if let cacheName = info.mpvMd5, ThumbnailCache.fileIsCached(forName: cacheName, forVideo: info.currentURL) {
        log("Found thumbnail cache")
        thumbnailQueue.async {
          if let thumbnails = ThumbnailCache.read(forName: cacheName) {
            self.info.thumbnails = thumbnails
            self.info.thumbnailsReady = true
            self.info.thumbnailsProgress = 1
            self.refreshTouchBarSlider()
          } else {
            self.log("Cannot read thumbnail from cache", level: .error)
          }
        }
      } else {
        log("Request new thumbnails")
        ffmpegController.generateThumbnail(forFile: url.path, thumbWidth:Int32(Preference.integer(for: .thumbnailWidth)))
      }
    }
  }

  func makeTouchBar() -> NSTouchBar {
    log("Activating Touch Bar")
    needsTouchBar = true
    // The timer that synchronizes the UI is shutdown to conserve energy when the OSC is hidden.
    // However the timer can't be stopped if it is needed to update the information being displayed
    // in the touch bar. If currently playing make sure the timer is running.
    refreshSyncUITimer()
    return touchBarSupport.touchBar
  }

  func refreshTouchBarSlider() {
    DispatchQueue.main.async {
      self.touchBarSupport.touchBarPlaySlider?.needsDisplay = true
    }
  }

  // MARK: - Getting info

  func getTrackInfo() {
    info.audioTracks.removeAll(keepingCapacity: true)
    info.videoTracks.removeAll(keepingCapacity: true)
    info.$subTracks.withLock {
      $0.removeAll(keepingCapacity: true)
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
          $0.append(track)
        default:
          break
        }
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
    info.$playlist.withLock { playlist in
      playlist.removeAll()
      let playlistCount = mpv.getInt(MPVProperty.playlistCount)
      for index in 0..<playlistCount {
        let playlistItem = MPVPlaylistItem(filename: mpv.getString(MPVProperty.playlistNFilename(index))!,
                                           isCurrent: mpv.getFlag(MPVProperty.playlistNCurrent(index)),
                                           isPlaying: mpv.getFlag(MPVProperty.playlistNPlaying(index)),
                                           title: mpv.getString(MPVProperty.playlistNTitle(index)))
        playlist.append(playlistItem)
      }
    }
  }

  func getChapters() {
    log("Reloading chapter list", level: .verbose)
    var chapters: [MPVChapter] = []
    let chapterCount = mpv.getInt(MPVProperty.chapterListCount)
    for index in 0..<chapterCount {
      let chapter = MPVChapter(title:     mpv.getString(MPVProperty.chapterListNTitle(index)),
                               startTime: mpv.getDouble(MPVProperty.chapterListNTime(index)),
                               index:     index)
      chapters.append(chapter)
    }
    // Instead of modifying existing list, overwrite reference to prev list.
    // This will avoid concurrent modification crashes
    info.chapters = chapters

    syncUI(.chapterList)
  }

  // MARK: - Notifications

  func postNotification(_ name: Notification.Name) {
    NotificationCenter.default.post(Notification(name: name, object: self))
  }

  // MARK: - Utils

  func checkTicket(_ ticket: Int) throws {
    if backgroundQueueTicket != ticket {
      throw TicketExpiredError.ticketExpired
    }
  }

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
        info.audioEqFilter = filter
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
    guard Preference.bool(for: .preventScreenSaver) else {
      SleepPreventer.allowSleep()
      return
    }
    // Look for players actively playing that are not in music mode and are not just playing audio.
    for player in playing {
      guard player.info.state == .playing,
            player.info.isAudio != .isAudio && !player.isInMiniPlayer else { continue }
      SleepPreventer.preventSleep()
      return
    }
    // Now look for players in music mode or playing audio.
    for player in playing {
      guard player.info.state == .playing,
            player.info.isAudio == .isAudio || player.isInMiniPlayer else { continue }
      // Either prevent the screen saver from activating or prevent system from sleeping depending
      // upon user setting.
      SleepPreventer.preventSleep(allowScreenSaver: Preference.bool(for: .allowScreenSaverForAudio))
      return
    }
    // No players are actively playing.
    SleepPreventer.allowSleep()
  }
}


extension PlayerCore: FFmpegControllerDelegate {

  func didUpdate(_ thumbnails: [FFThumbnail]?, forFile filename: String, withProgress progress: Int) {
    guard let currentFilePath = info.currentURL?.path, currentFilePath == filename else { return }
    log("Got new thumbnails, progress \(progress)")
    if let thumbnails = thumbnails {
      info.$thumbnails.withLock { $0.append(contentsOf: thumbnails) }
    }
    info.thumbnailsProgress = Double(progress) / Double(ffmpegController.thumbnailCount)
    refreshTouchBarSlider()
  }

  func didGenerate(_ thumbnails: [FFThumbnail], forFile filename: String, succeeded: Bool) {
    guard let currentFilePath = info.currentURL?.path, currentFilePath == filename else { return }
    log("Got all thumbnails, succeeded=\(succeeded)")
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

class NowPlayingInfoManager {

  /// Update the information shown by macOS in `Now Playing`.
  ///
  /// The macOS [Control Center](https://support.apple.com/guide/mac-help/quickly-change-settings-mchl50f94f8f/mac)
  /// contains a `Now Playing` module. This module can also be configured to be directly accessible from the menu bar.
  /// `Now Playing` displays the title of the media currently  playing and other information about the state of playback. It also can be
  /// used to control playback. IINA is fully integrated with the macOS `Now Playing` module.
  ///
  /// - Note: See [Becoming a Now Playable App](https://developer.apple.com/documentation/mediaplayer/becoming_a_now_playable_app)
  ///         and [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
  ///         for more information.
  ///
  /// - Important: This method **must** be run on the main thread because it references `PlayerCore.lastActive`.
  static func updateInfo(state: MPNowPlayingPlaybackState? = nil, withTitle: Bool = false) {
    let center = MPNowPlayingInfoCenter.default()
    var info = center.nowPlayingInfo ?? [String: Any]()

    let activePlayer = PlayerCore.lastActive
    guard activePlayer.info.state.active else { return }

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
