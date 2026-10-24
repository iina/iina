//
//  PlayerCore.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import ImageIO

private enum ScreenshotImageDecoder {
  static func decode(_ url: URL, enableFFmpeg: Bool) -> NSImage? {
    autoreleasepool {
      let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true,
                                     kCGImageSourceShouldAllowFloat: true]
      if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
         let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) {
        return NSImage(cgImage: image, size: .zero)
      }
      guard enableFFmpeg else { return nil }
      Logger.log("Using FFmpeg to decode screenshot: \(url)")
      return FFmpegController.createNSImage(withContentsOf: url)
    }
  }
}

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

  static var nonIdle: [PlayerCore] {
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

  /// Similar to `activeOrNew`, but supports inverting the action
  static func activeOrNewForMenuAction(isAlternative: Bool) -> PlayerCore {
    // since it's from a menu item, there is at least one player core
    let useNew = Preference.bool(for: .alwaysOpenInNewWindow) != isAlternative
    return useNew ? newPlayerCore : active
  }

  /**
   Opens the URLs in the right window or windows, depending on user settings.

   - Returns: `nil` if no further action is needed, like opened a BD Folder; otherwise the
   count of playable files.
   */
  @discardableResult
  static func openURLs(_ urls: [URL], invertOpenInNewWindow: Bool = false) -> Int? {
    var openInCurrentWindow = !Preference.bool(for: .alwaysOpenInNewWindow)
    if invertOpenInNewWindow {
      openInCurrentWindow = !openInCurrentWindow
    }
    if openInCurrentWindow {
      // open all urls in the active window if any (or, all in one new window)
      return active.openURLs(urls)
    } else if
      urls.count > 1,
      Preference.bool(for: .groupSimultaneousOpensInPlaylist)
    {
      // create new window, open all urls in that window
      // this purposefully ignores `allowDuplicatePlayers`
      return newPlayerCore.openURLs(urls)
    } else {
      // open each url in its own new window. accumulate the return values
      return urls.reduce(nil) { currentReturnValue, url in
        // skip if url is already open in some player
        if !Preference.bool(for: .allowDuplicatePlayers) {
          let activePlayerCores = playerCores.filter { $0.info.state != .idle }
          let relevantActivePlayerCore = activePlayerCores.first { $0.info.currentURL == url }

          if let relevantActivePlayerCore {
            relevantActivePlayerCore.currentController.window?.makeKeyAndOrderFront(nil)
            return currentReturnValue
          }
        }

        // open url, combine open result into return value
        let openResult = newPlayerCore.openURLs([url])

        return
          if let openResult {
            (currentReturnValue ?? 0) + openResult
          } else {
            currentReturnValue
          }
      }
    }
  }

  // MARK: - Fields

  private var observers: [NSObjectProtocol] = []

  lazy var subsystem = Logger.makeSubsystem("player\(label!)", ["play.circle"])

  func log(_ message: @autoclosure () -> String, level: Logger.Level = .debug) {
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

  /// `true` if this Mac is _known to_ have a  [Touch Bar](https://support.apple.com/guide/mac-help/use-the-touch-bar-mchlbfd5b039/mac).
  ///
  /// In order to adhere to energy efficiency best practices IINA should stop the timer that synchronizes the UI when it is not needed.
  /// As one job of the timer is to update the Touch Bar on Macs that have one, IINA needs information such as:
  /// - Does this host have a Touch Bar?
  /// - Is the Touch Bar configured to show app controls?
  /// - Is the Touch Bar awake?
  /// - Is the host being operated in closed clamshell mode?
  ///
  /// This is the kind of information needed to avoid running the timer and updating controls that are not visible. Unfortunately in the
  /// documentation for [NSTouchBar](https://developer.apple.com/documentation/appkit/nstouchbar) Apple
  /// indicates "There’s no need, and no API, for your app to know whether or not there’s a Touch Bar available". So this property is
  /// set based off whether `AppKit` has requested that a `NSTouchBar` object be created by calling
  /// [MakeTouchBar](https://developer.apple.com/documentation/appkit/nsresponder/2544690-maketouchbar).
  /// This property is used to avoid running the timer on Macs that do not have a Touch Bar. It also may avoid running the timer when a
  /// MacBook with a Touch Bar is being operated in closed clamshell mode as `AppKit` will not call `MakeTouchBar` when the
  /// Touch Bar is asleep.
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
  private var hasSentMPVQuit = false
  private var shutdownRequestedAfterStop = false

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

  let osdFeedbackOrigins = OSDFeedbackOrigins()
  private var osdFeedbackOrigin = OSDFeedbackOrigin.command

  var currentOSDFeedbackOrigin: OSDFeedbackOrigin { Thread.isMainThread ? osdFeedbackOrigin : .command }

  @discardableResult
  func withOSDFeedbackOrigin<T>(_ origin: OSDFeedbackOrigin, _ action: () -> T) -> T {
    dispatchPrecondition(condition: .onQueue(.main))
    let previous = osdFeedbackOrigin
    osdFeedbackOrigin = origin
    defer { osdFeedbackOrigin = previous }
    return action()
  }

  @discardableResult
  func performSidebarChange<T>(_ action: () -> T) -> T { withOSDFeedbackOrigin(.sidebar, action) }

  func preservingOSDFeedbackOrigin<T>(_ action: @escaping () -> T) -> () -> T {
    let origin = currentOSDFeedbackOrigin
    return { [weak self] in
      guard let self else { return action() }
      return self.withOSDFeedbackOrigin(origin, action)
    }
  }

  private enum CropRefreshUpdate: Hashable { case video, tracks, filters, videoParams }
  private var pausedCropRefresh: (generation: Int, updates: Set<CropRefreshUpdate>, showsSeekOSD: Bool)?
  private var videoGeometryOSDRefresh: (token: UUID, generation: Int, showsSeekOSD: Bool)?
  private var userSeekOSDIntent: (token: UUID, generation: Int)?
  private var startedSeekOSDIntent: UUID?

  var isRefreshingPausedCrop: Bool {
    pausedCropRefresh?.generation == info.trackSelectionGeneration && info.state.active
  }

  var shouldShowSeekOSD: Bool {
    // mpv also seeks internally when refreshing filters or rebuilding a graph.
    // Only a deliberate seek request should publish time/progress feedback.
    guard info.state.active,
          userSeekOSDIntent?.generation == info.trackSelectionGeneration else { return false }
    let geometry = videoGeometryOSDRefresh
    let refreshingGeometry = geometry?.generation == info.trackSelectionGeneration && info.state.active
    return (!refreshingGeometry || geometry?.showsSeekOSD == true) &&
      (!isRefreshingPausedCrop || pausedCropRefresh?.showsSeekOSD == true)
  }

  @discardableResult
  func userInitiatedSeek() -> UUID {
    let token = UUID()
    userSeekOSDIntent = (token, info.trackSelectionGeneration)
    pausedCropRefresh?.showsSeekOSD = true
    if videoGeometryOSDRefresh?.generation == info.trackSelectionGeneration {
      videoGeometryOSDRefresh?.showsSeekOSD = true
    }
    return token
  }

  func cancelUserInitiatedSeek(_ token: UUID) {
    guard userSeekOSDIntent?.token == token else { return }
    userSeekOSDIntent = nil
    if startedSeekOSDIntent == token { startedSeekOSDIntent = nil }
  }

  func seekOSDDidStart() {
    startedSeekOSDIntent = userSeekOSDIntent?.generation == info.trackSelectionGeneration
      ? userSeekOSDIntent?.token : nil
  }

  func seekOSDDidRestart() {
    // A restart from an older seek must not consume a newer pending user action.
    if let startedSeekOSDIntent, userSeekOSDIntent?.token == startedSeekOSDIntent {
      userSeekOSDIntent = nil
    }
    startedSeekOSDIntent = nil
  }

  /// Scope only unsolicited seek OSD; native seeking, playback and geometry
  /// notifications retain their normal lifecycle. A superseding change owns a
  /// new token, while deliberate seeking remains visible through the overlap.
  func beginVideoGeometryOSDRefresh() -> UUID {
    dispatchPrecondition(condition: .onQueue(.main))
    let token = UUID()
    let generation = info.trackSelectionGeneration
    let inheritedIntent = videoGeometryOSDRefresh?.generation == generation &&
      videoGeometryOSDRefresh?.showsSeekOSD == true
    let explicitIntent = userSeekOSDIntent?.generation == generation
    videoGeometryOSDRefresh = (token, generation, inheritedIntent || explicitIntent)
    return token
  }

  func endVideoGeometryOSDRefresh(_ token: UUID) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let refresh = videoGeometryOSDRefresh, refresh.token == token else { return }
    // The ready frame can reach main before the event reader has dispatched its
    // preceding refresh SEEK. Drain those events before releasing this scope.
    mpv.afterPendingEvents { [weak self] in
      guard let self, self.videoGeometryOSDRefresh?.token == token,
            self.info.trackSelectionGeneration == refresh.generation else { return }
      self.videoGeometryOSDRefresh = nil
    }
  }

  private func cancelVideoGeometryOSDRefresh() {
    osdFeedbackOrigins.reset()
    videoGeometryOSDRefresh = nil
    userSeekOSDIntent = nil
    startedSeekOSDIntent = nil
  }

  private func beginPausedCropRefresh() {
    guard info.state == .paused else { return }
    if !isRefreshingPausedCrop {
      pausedCropRefresh = (info.trackSelectionGeneration, [],
                           userSeekOSDIntent?.generation == info.trackSelectionGeneration)
    }
    mainWindow.videoView.displayActive()
  }

  func requestNativeCropFrame() {
    guard info.state.active else { return }
    // A filter mutation already refreshes paused video. Seeking here repeats
    // that decode after playback-restart, delaying both native handoffs.
    mainWindow.videoView.videoLayer.update(force: true)
  }

  private func deferCropRefreshUpdate(_ update: CropRefreshUpdate) -> Bool {
    guard isRefreshingPausedCrop else { return false }
    pausedCropRefresh?.updates.insert(update)
    return true
  }

  private func finishPausedCropRefresh() {
    let refresh = pausedCropRefresh
    pausedCropRefresh = nil
    guard let refresh, refresh.generation == info.trackSelectionGeneration, info.state.active else { return }
    if refresh.updates.contains(.video) { onVideoReconfig(outputIsReady: true) }
    if refresh.updates.contains(.tracks) { trackListChanged() }
    if refresh.updates.contains(.filters) { vfChanged() }
    if refresh.updates.contains(.videoParams) { videoParamsChanged() }
  }

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
    isInMiniPlayer ? miniPlayer.isPlaylistVisible : mainWindow.sidebars.isShowing(.playlist)
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

  /// Whether to only use the URL's filename when calculating the mpv
  /// [Watch Later](https://mpv.io/manual/stable/#watch-later) MD5 sum.
  ///
  /// This supports the mpv
  /// [ignore-path-in-watch-later-config](https://mpv.io/manual/stable/#options-ignore-path-in-watch-later-config)
  /// option. As this option is only used by advanced users there is intentionally no support in IINA's UI for this option. This is also an
  /// option that you would set and not change as changing it means existing watch later files will no longer be found. For this reason
  /// IINA does not support dynamic changes to this option. The value of this option is obtained and cached. Setting this option
  /// requires IINA to be restarted.
  lazy var ignorePathInWatchLaterConfig: Bool = {
    let ignorePath = mpv.getFlag(MPVOption.WatchLater.ignorePathInWatchLaterConfig)
    if ignorePath {
      log("Will use filename instead of path when calculating watch later MD5 sum")
    }
    return ignorePath
  }()

  /// Whether to auto load files when opening the URL given in `pendingUrl`.
  private var pendingAutoLoad = false

  /// URL to open once an outstanding mpv stop command completes.
  private var pendingUrl: URL?

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
    TouchBarSettings.shared.addObserver(self, forKey: .PresentationModeFnModes)
    TouchBarSettings.shared.addObserver(self, forKey: .PresentationModeGlobal)
    TouchBarSettings.shared.addObserver(self, forKey: .PresentationModePerApp)
  }

  func observe(_ name: Notification.Name, block: @escaping (Notification) -> Void) {
    observers.append(NotificationCenter.default.addObserver(
      forName: name, object: self, queue: .main, using: block))
  }

  deinit {
    observers.forEach {
      NotificationCenter.default.removeObserver($0)
    }
  }

  // MARK: - Plugins

  static func reloadPluginForAll(_ plugin: JavascriptPlugin, forced: Bool = false) {
    playerCores.forEach { $0.reloadPlugin(plugin, forced: forced) }
    AppDelegate.shared.menuController?.updatePluginMenu()
  }

  func clearPlugins() {
    pluginMap.removeAll()
    plugins.removeAll()
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
    mainWindow.sidebars.pluginView.updatePluginTabs()
  }

  // MARK: - Control

  private func open(_ url: URL?, shouldAutoLoad: Bool = false) {
    guard let url else {
      log("empty file path or url", level: .error)
      return
    }
    guard info.state != .stopping else {
      // The mpv core is currently processing an asynchronous stop command. To avoid the complexity
      // of coordinating two mpv commands executing at the same time, wait until the stop command
      // finishes and the core becomes idle before sending the loadfile command. The stop command
      // normally does not take long to complete, so this should not be noticeable to the user.
      log("Waiting for stop command to finish before opening: \(url.absoluteString)")
      pendingAutoLoad = shouldAutoLoad
      pendingUrl = url
      return
    }
    let isNetwork = !url.isFileURL || url.pathExtension.starts(with: "m3u")
    if isNetwork, info.state != .idle, let currentWindow {
      // Replace the player window with the loading window. Closing the player window will result in
      // an asynchronous stop command being sent to mpv. As described above, delay sending the
      // loadfile command until the stop command finishes.
      log("Closing window before opening: \(url.absoluteString)")
      pendingAutoLoad = shouldAutoLoad
      pendingUrl = url
      currentWindow.close()
      return
    }
    log("Open URL: \(url.absoluteString)")
    if shouldAutoLoad {
      info.shouldAutoLoadFiles = true
    }
    info.hdrEnabled = Preference.bool(for: .enableHdrSupport)
    let path = url.isFileURL ? url.path : url.absoluteString
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
      mpv.playlistAppend(url.isFileURL ? url.path : url.absoluteString)
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

  /// Open the given media in the main window.
  /// - Important: This method will ensure playback is paused before running the load command. If playback is not paused, audio
  ///     can start playing before video is shown. This is most noticeable with high resolution videos encoded with newer high
  ///     compression codecs (such as AV1), when running on older Macs that lack support for hardware decoding of the codec
  ///     used. Playback will be started once the video has been loaded and the size of the video is known (unless the "Pause"
  ///     setting is enabled under "When media is opened"). Playback is only paused before loading when media is manually opened
  ///     by the user in order to not disrupt gapless audio.
  /// - Parameters:
  ///   - path: Path to the media to open.
  ///   - url: URL of the media to open.
  ///   - isNetwork: Whether the media must be streamed over the network.
  private func openMainWindow(path: String, url: URL, isNetwork: Bool) {
    log("Opening \(path) in main window")
    info.currentURL = url
    info.mpvMd5 = Utility.mpvWatchLaterMd5(url, ignorePathInWatchLaterConfig)
    info.isNetworkResource = isNetwork
    info.audioTracks = []
    info.chapters = []
    info.playlist = []
    info.isShuffled = false
    info.subTracks = []
    info.thumbnails = []
    info.thumbnailsReady = false
    info.videoDuration = nil
    info.videoHeight = nil
    info.videoPosition = nil
    info.videoTracks = []
    info.videoWidth = nil
    if isNetwork {
      AppDelegate.shared.openURLWindow.showLoadingScreen(playerCore: self)
    }

    let _ = mainWindow.window
    mainWindow.pendingShow = true
    miniPlayer.pendingShow = true
    initialWindow.close()

    if !mpv.getFlag(MPVOption.PlaybackControl.pause) {
      log("Pausing playback before running load command")
      mpv.setFlag(MPVOption.PlaybackControl.pause, true, level: .verbose)
    }

#if USE_ICC_PROFILE_AUTO // See VideoView.setICCProfile.
    // If this mpv core is being reused icc-profile-auto may have been left set to true. This option
    // MUST be reset to false to avoid a crash that occurs if the mpv OSD is being used. Another way
    // to fix this would be to add this option to the mpv reset-on-next-file option. However the
    // user might override IINA and set that option themselves and not include icc-profile-auto.
    // Better to directly reset icc-profile-auto. See issue #5727 for details.
    mpv.setFlag(MPVOption.GPURendererOptions.iccProfileAuto, false)
#endif

    // Delay force-window until an actual file load to avoid Xcode-launched app startup hanging
    // while mpv tries to create a VO before IINA has entered its normal media-open path.
    mpv.setString(MPVOption.Window.forceWindow, "yes", level: .verbose)

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
    mpv.addHook(.onUnLoad, hook: MPVHookValue(withBlock: { [weak self] next in
      DispatchQueue.main.async {
        self?.saveVideoGeometryForCurrentMedia()
        next()
      }
    }))
    mpv.addHook(.onLoad, hook: MPVHookValue(withBlock: { [weak self] next in
      DispatchQueue.main.async {
        guard let self else { next(); return }
        self.clearTrackGraphForNewFile()
        self.prepareVideoGeometryForNewFile()
        self.prepareMultivideoDemuxer(then: next)
      }
    }))
    mpv.addHook(.onPreLoaded, hook: MPVHookValue(withBlock: { [weak self] next in
      DispatchQueue.main.async {
        self?.restoreVideoGeometryForCurrentMedia()
        next()
      }
    }))
    events.emit(.mpvInitialized)

    let audioDevice = Preference.string(for: .audioDevice)!
    if !getAudioDevices().contains(where: { $0.name == audioDevice }) {
      log("Audio device configured in settings not found, will default to auto:\n  \(audioDevice)")
      setAudioDevice("auto")
    }
  }

  func initVideo() {
    // init mpv render context.
    mpv.mpvInitRendering()
    // `force-window=immediate` makes audio-only subtitle rendering work with `vo=libmpv`,
    // but setting it before render initialization can race the VO thread against IINA's
    // render context setup. Switch to `immediate` only after the render context exists.
    mpv.setString(MPVOption.Window.forceWindow, "immediate", level: .verbose)
    mainWindow.videoView.startDisplayLink()
    log("Initialized rendering")
    MemoryUsage.shared.logUsage("after rendering initialized")
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
    guard info.state != .shutDown, !hasSentMPVQuit else { return }
    if info.state == .stopping {
      shutdownRequestedAfterStop = true
      pendingUrl = nil
      return
    }
    shutdownRequestedAfterStop = false
    cancelVideoGeometryOSDRefresh()
    cancelScreenshotRequests()
    info.state = .shuttingDown
    guard !backgroundTaskInUse else { return }
    hasSentMPVQuit = true
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
    cancelVideoGeometryOSDRefresh()
    cancelScreenshotRequests(close: true)
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
    guard !isInMiniPlayer, info.state.active, mainWindow.loaded,
          !mainWindow.interactiveMode.isActive, !mainWindow.isCropTransitionInProgress,
          mainWindow.pipStatus == .notInPIP, !mainWindow.isFullscreenTransitionInProgress,
          mainWindow.videoView.superview === mainWindow.videoViewContainer else { return }
    log("Switch to mini player, automatically=\(automatically)")
    if !automatically {
      // Toggle manual override
      overrideAutoSwitchToMusicMode = !overrideAutoSwitchToMusicMode
      Logger.log("Changed overrideAutoSwitchToMusicMode to \(overrideAutoSwitchToMusicMode)",
                 level: .verbose, subsystem: subsystem)
    }

    // The call to orderOut handles being in full screen mode if using the AppKit supplied full
    // screen mode, but if legacy full screen mode is being used then IINA needs to handle it.
    if mainWindow.fsState.isFullscreen, Preference.bool(for: .useLegacyFullScreen) {
      mainWindow.toggleWindowFullScreen()
    }
    // hide main window
    mainWindow.window?.orderOut(self)

    let needRestoreLayout = !miniPlayer.loaded
    let _ = miniPlayer.window

    miniPlayer.updateTitle()
    refreshSyncUITimer()
    let playlistView = mainWindow.sidebars.playlistView
    // force initialize the view
    let _ = playlistView.view
    let videoView = mainWindow.videoView
    // reset down shift for playlistView
    mainWindow.sidebars.playlistView.downShift = 0
    // hide sidebar
    if mainWindow.sidebars.isAnyVisible {
      mainWindow.sidebars.hideAllSideBars(animate: false)
    }

    // move playlist view
    playlistView.view.removeFromSuperview()
    miniPlayer.playlistWrapperView.addSubview(playlistView.view)
    playlistView.view.padding(.all)
    // move video view
    mainWindow.liveText.clearAnalysis()
    videoView.removeFromSuperview()
    miniPlayer.videoWrapperView.addSubview(videoView, positioned: .below, relativeTo: nil)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": videoView])

    miniPlayer.refreshArtworkVisibility()
    let (width, height) = miniPlayer.videoSizeForDisplayInMusicMode()
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
    mainWindow.forceDraw("entered music mode")
    postNotification(.iinaMusicModeChanged)
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
    guard isInMiniPlayer else { return }
    log("Switch to normal window from mini player, automatically=\(automatically)")
    if !automatically {
      overrideAutoSwitchToMusicMode = !overrideAutoSwitchToMusicMode
      Logger.log("Changed overrideAutoSwitchToMusicMode to \(overrideAutoSwitchToMusicMode)",
                 level: .verbose, subsystem: subsystem)
    }
    mainWindow.sidebars.playlistView.view.removeFromSuperview()
    mainWindow.sidebars.playlistView.isInMiniPlayer = false
    // add back video view
    miniPlayer.videoViewAspectConstraint?.isActive = false
    miniPlayer.videoViewAspectConstraint = nil
    mainWindow.addVideoViewToWindow()
    mainWindow.oscFloatingView.updatePosition()

    // hide mini player
    miniPlayer.window?.orderOut(nil)
    isInMiniPlayer = false

    mainWindow.pendingShow = true
    if showMainWindow {
      currentController.setupUI()
      mainWindow.updateTitle()
      notifyWindowVideoSizeChanged()
    }

    mainWindow.forceDraw("exited music mode")
    mainWindow.liveText.requestAnalysis()
    postNotification(.iinaMusicModeChanged)
    events.emit(.musicModeChanged, data: false)
  }

  // MARK: - MPV commands

  func togglePause(_ set: Bool? = nil) {
    info.state == .paused ? resume() : pause()
  }

  /// Pause playback.
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
    log("Pausing playback")
    mpv.setFlag(MPVOption.PlaybackControl.pause, true, level: .verbose)
  }

  /// Resume playback.
  /// - Important: Although primary responsibility for ensuring the display link is running when playback is in progress belongs to
  ///     the `pauseChanged` method, this method calls `displayActive` to provide more time for the display link to start up.
  func resume() {
    guard info.state.active else { return }
    log("Resuming playback")
    mainWindow.videoView.displayActive()
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
    guard info.state != .shuttingDown, info.state != .shutDown else { return }
    cancelVideoGeometryOSDRefresh()
    cancelScreenshotRequests()
    pausedCropRefresh = nil
    savePlaybackPosition()

    // The player may already be stopped in which case the state must not be set to stopping.
    if info.state != .idle {
      // Setting of state must come after saving playback position or that method will not save the
      // watch later configuration.
      info.state = .stopping

      // Make sure playback is paused to free up machine resources when quitting.
      if !mpv.getFlag(MPVOption.PlaybackControl.pause) {
        log("Pausing playback before sending stop command")
        mpv.setFlag(MPVOption.PlaybackControl.pause, true, level: .verbose)
      }
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
    guard info.state.active else { return }
    let newState = set ?? !mpv.getFlag(MPVOption.Audio.mute)
    mpv.setFlag(MPVOption.Audio.mute, newState)
  }

  func seek(percent: Double, forceExact: Bool = false) {
    guard info.state.active else { return }
    userInitiatedSeek()
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
    guard info.state.active else { return }
    userInitiatedSeek()
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
    guard info.state.active else { return }
    userInitiatedSeek()
    mpv.command(.seek, args: ["\(absoluteSecond)", "absolute+exact"])
  }

  func frameStep(backwards: Bool) {
    if backwards { userInitiatedSeek() }
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

  private final class ScreenshotRequest {
    let id: UInt64
    let generation: Int
    let mediaURL: URL?
    let saveToFile: Bool
    let copyToClipboard: Bool
    let showPreview: Bool
    let enableFFmpeg: Bool
    var feedback: UUID?
    var outputURL: URL?
    var receivedReply = false
    var cancelled = false

    init(id: UInt64, generation: Int, mediaURL: URL?, feedback: UUID) {
      self.id = id
      self.generation = generation
      self.mediaURL = mediaURL
      self.feedback = feedback
      saveToFile = Preference.bool(for: .screenshotSaveToFile)
      copyToClipboard = Preference.bool(for: .screenshotCopyToClipboard)
      showPreview = Preference.bool(for: .screenshotShowPreview)
      enableFFmpeg = Preference.bool(for: .enableFFmpegImageDecoder)
    }
  }

  private static let screenshotQueue = DispatchQueue(label: "com.colliderli.iina.screenshot", qos: .userInitiated)
  private var screenshotRequestSequence: UInt64 = 0
  private var screenshotRequests: [UInt64: ScreenshotRequest] = [:]

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
    dispatchPrecondition(condition: .onQueue(.main))
    let saveToFile = Preference.bool(for: .screenshotSaveToFile)
    let saveToClipboard = Preference.bool(for: .screenshotCopyToClipboard)
    guard saveToFile || saveToClipboard else {
      log("Ignoring screenshot request: all forms of screenshots are disabled in prefs", level: .warning)
      return false
    }

    guard info.state.loaded, !info.activeTrackIDs(.video).isEmpty else {
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

    guard screenshotRequestSequence < MPVController.UserData.screenshotSequenceMask else { return false }
    screenshotRequestSequence += 1
    let id = MPVController.UserData.screenshot | screenshotRequestSequence
    let request = ScreenshotRequest(id: id, generation: info.trackSelectionGeneration,
                                    mediaURL: info.currentURL, feedback: mainWindow.beginOperationFeedback())
    screenshotRequests[id] = request
    let status = mpv.asyncCommand(.screenshot, args: commandFlags, checkError: false, replyUserdata: id)
    if status < 0 {
      // Failed submission has no COMMAND_REPLY, so release feedback here.
      screenshotCallback(requestID: id, error: status, fileURL: nil)
    }
    return status >= 0
  }

  private func isCurrentScreenshotRequest(_ request: ScreenshotRequest) -> Bool {
    !request.cancelled && info.state.loaded && info.trackSelectionGeneration == request.generation
      && info.currentURL == request.mediaURL
  }

  private static func removeTemporaryScreenshot(_ url: URL?) {
    guard let url else { return }
    screenshotQueue.async {
      let cache = Utility.screenshotCacheURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
      let path = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
      // Never delete saved files or another destination inferred from directory ordering.
      guard path.count > cache.count, Array(path.prefix(cache.count)) == cache else { return }
      try? FileManager.default.removeItem(at: url)
    }
  }

  private func finishScreenshotRequest(_ request: ScreenshotRequest) {
    guard screenshotRequests.removeValue(forKey: request.id) != nil else { return }
    if let feedback = request.feedback { mainWindow?.endOperationFeedback(feedback) }
    request.feedback = nil
    if !request.saveToFile { Self.removeTemporaryScreenshot(request.outputURL) }
  }

  func cancelScreenshotRequests(close: Bool = false) {
    dispatchPrecondition(condition: .onQueue(.main))
    for request in Array(screenshotRequests.values) {
      request.cancelled = true
      if let feedback = request.feedback { mainWindow?.endOperationFeedback(feedback) }
      request.feedback = nil
      // Keep pending IDs until their reply identifies a temporary output. At
      // core shutdown no more replies are possible; workers own their URL copies.
      if close { finishScreenshotRequest(request) }
    }
  }

  func screenshotCallback(requestID: UInt64, error: Int32, fileURL: URL?) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let request = screenshotRequests[requestID], !request.receivedReply else { return }
    request.receivedReply = true
    request.outputURL = fileURL
    guard isCurrentScreenshotRequest(request) else { finishScreenshotRequest(request); return }
    guard error >= 0 else {
      finishScreenshotRequest(request)
      log("Cannot take a screenshot, mpv API error: \(error)", level: .error)
      Utility.showAlert("screenshot.error_taking")
      return
    }
    guard let fileURL else {
      finishScreenshotRequest(request)
      log("Screenshot reply did not include its output filename", level: .error)
      return
    }
    let needsImage = request.copyToClipboard || request.showPreview
    let enableFFmpeg = request.enableFFmpeg
    let temporary = !request.saveToFile
    Self.screenshotQueue.async { [weak self] in
      let exists = FileManager.default.fileExists(atPath: fileURL.path)
      let image = exists && needsImage ? ScreenshotImageDecoder.decode(fileURL, enableFFmpeg: enableFFmpeg) : nil
      DispatchQueue.main.async { [weak self] in
        guard let self else {
          if temporary { Self.removeTemporaryScreenshot(fileURL) }
          return
        }
        guard let current = self.screenshotRequests[requestID] else {
          if temporary { Self.removeTemporaryScreenshot(fileURL) }
          return
        }
        self.finishDecodedScreenshot(current, fileExists: exists, image: image)
      }
    }
  }

  private func finishDecodedScreenshot(_ request: ScreenshotRequest, fileExists: Bool, image: NSImage?) {
    dispatchPrecondition(condition: .onQueue(.main))
    defer { finishScreenshotRequest(request) }
    guard isCurrentScreenshotRequest(request), fileExists else { return }
    if request.copyToClipboard, let image {
      NSPasteboard.general.clearContents()
      _ = NSPasteboard.general.writeObjects([image])
    }
    guard request.showPreview, let image else {
      sendOSD(.screenshot)
      return
    }
    let osdView = ScreenshootOSDView()
    osdView.setImage(image, size: image.size.shrink(toSize: NSSize(width: 300, height: 200)),
                     fileURL: request.saveToFile ? request.outputURL : nil)
    sendOSD(.screenshot, forcedTimeout: 5, accessoryView: osdView.view, context: osdView)
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
    log("Synchronized info.abLoopStatus \(info.abLoopStatus)")

    // If window is not loaded the play slider knobs can't be synchronized.
    guard mainWindow.loaded, info.state.active else { return }
    // The play slider has knobs representing the loop points, make insure the slider is in sync.
    mainWindow.syncSlider()
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
    if let loopFileStatus, let count = Int(loopFileStatus), count != 0 {
      return .file
    }
    let loopPlaylistStatus = mpv.getString(MPVOption.PlaybackControl.loopPlaylist)
    guard loopPlaylistStatus != "inf", loopPlaylistStatus != "force" else { return .playlist }
    guard let loopPlaylistStatus, let count = Int(loopPlaylistStatus) else {
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
    if info.isShuffled {
      mpv.command(.playlistUnshuffle)
      info.isShuffled = false
    } else {
      mpv.command(.playlistShuffle)
      info.isShuffled = true
    }
    postNotification(.iinaPlaylistChanged)
  }

  func setVolume(_ volume: Double, constrain: Bool = true) {
    guard info.state.active else { return }
    let maxVolume = Preference.integer(for: .maxVolume)
    let constrainedVolume = volume.clamped(to: 0...Double(maxVolume))
    let appliedVolume = constrain ? constrainedVolume : volume
    let shouldSendConstrainedVolumeOSD =
      constrain && volume != constrainedVolume && info.volume == appliedVolume
    info.volume = appliedVolume
    mpv.setDouble(MPVOption.Audio.volume, appliedVolume, level: .verbose)
    Preference.set(constrainedVolume, for: .softVolume)
    if shouldSendConstrainedVolumeOSD {
      // mpv won't send MPV_EVENT_PROPERTY_CHANGE if the volume is unchanged.
      sendOSD(.volume(constrainedVolume))
    }
  }

  /// Native MKV seeks follow one video's cues and can skip keyframes in separate clusters.
  /// Select FFmpeg before opening multivideo MKVs; retain explicit demuxer overrides.
  private func prepareMultivideoDemuxer(then next: @escaping () -> Void) {
    guard (mpv.getString(MPVOption.Demuxer.demuxer) ?? "").isEmpty,
          let path = mpv.getString(MPVProperty.path) else { next(); return }
    let url = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
    guard let url, url.isFileURL,
          ["mkv", "mk3d", "webm"].contains(url.pathExtension.lowercased()),
          (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { next(); return }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let useLavf = FFmpegController.hasMultipleVideoTracks(inMatroskaFile: url.path)
      DispatchQueue.main.async {
        if useLavf {
          self?.mpv.setString("file-local-options/demuxer", "lavf")
        }
        next()
      }
    }
  }

  var scopedTrackSettings = TrackProcessingState()
  var scopedCropPreview: ScopedTrackCropPreview?
  private var defaultVideoGeometry: MediaVideoGeometryState?
  private var videoGeometrySession: [URL: MediaVideoGeometryState] = [:]
  // info.currentURL can already name the replacement while the old file unloads.
  private var videoGeometryMediaURL: URL?
  private var videoGeometryIsLoaded = false
  private var ownedTrackGraph: String?
  private var persistentAudioInputs: Set<Int>?

  private var videoGeometryFilterLabels: Set<String> {
    [Constants.FilterName.crop, Constants.FilterName.flip,
     Constants.FilterName.mirror, Constants.FilterName.delogo]
  }

  /// Detach dormant media references along with active LUT users. The caller
  /// restores this snapshot if any engine or filesystem step fails.
  func detachSavedVideoLUT(atPath path: String) -> () -> Void {
    let sessions = videoGeometrySession
    let defaults = defaultVideoGeometry
    for (url, var value) in videoGeometrySession {
      value.removeLUT(atPath: path)
      videoGeometrySession[url] = value
    }
    defaultVideoGeometry?.removeLUT(atPath: path)
    return { [weak self] in
      self?.videoGeometrySession = sessions
      self?.defaultVideoGeometry = defaults
    }
  }

  private func readVideoGeometry() -> MediaVideoGeometryState {
    var result = MediaVideoGeometryState()
    for name in MediaVideoGeometryState.optionNames {
      result.options[name] = mpv.getString(name)
    }
    let filters = mpv.getFilters(MPVProperty.vf)
    for (index, filter) in filters.enumerated() {
      if filter.label.map({ videoGeometryFilterLabels.contains($0) }) == true {
        result.filters.append(filter.stringFormat)
        result.filterIndices.append(index)
      }
    }
    result.aspectDescription = MediaVideoGeometryState.aspectDescription(
      for: mpv.getDouble(MPVOption.Video.videoAspectOverride), preferred: info.unsureAspect)
    if let crop = filters.first(where: { $0.label == Constants.FilterName.crop }) {
      result.cropDescription = info.cropFilter?.isEqual(crop) == true &&
        !["", "None"].contains(info.unsureCrop) ? info.unsureCrop : "Custom"
    }
    result.video = scopedTrackSettings.video
    result.videoTarget = scopedTrackSettings.target(.videoGeometry)
    result.videoOrder = info.videoTrackOrder
    let active = info.activeTrackIDs(.video)
    result.activeVideo = info.videoTrackOrder.filter { active.contains($0) }
    result.activeVideo.append(contentsOf: active.sorted().filter { !result.activeVideo.contains($0) })
    return result
  }

  private func saveVideoGeometryForCurrentMedia() {
    guard videoGeometryIsLoaded, let url = videoGeometryMediaURL else { return }
    // Save committed values, not crop-preview/panscan overrides; hooks run on main before releasing mpv.
    mainWindow?.interactiveMode.exit()
    let originalPanscan = mainWindow?.videoAspectTransitionOriginalPanscan
    mainWindow?.finishVideoAspectTransition()
    var saved = readVideoGeometry()
    if let originalPanscan { saved.options["panscan"] = String(originalPanscan) }
    videoGeometrySession[url] = saved
    videoGeometryIsLoaded = false
  }

  private func prepareVideoGeometryForNewFile() {
    videoGeometryMediaURL = info.currentURL.map { $0.isFileURL ? $0.standardizedFileURL : $0 }
    videoGeometryIsLoaded = false
    // CLI/plugin options can follow mpv_initialize; capture them at the first load barrier, before file edits.
    if defaultVideoGeometry == nil { defaultVideoGeometry = readVideoGeometry() }
    // File-local defaults prevent geometry leaking between media; watch-later/config loading follows.
    if let defaultVideoGeometry { applyVideoGeometry(defaultVideoGeometry) }
  }

  private func restoreVideoGeometryForCurrentMedia() {
    if let url = videoGeometryMediaURL, let saved = videoGeometrySession[url] {
      // Runs after file configs/watch-later and before decoder initialization.
      applyVideoGeometry(saved)
    } else {
      syncVideoGeometryInfo()
    }
  }

  private func applyVideoGeometry(_ value: MediaVideoGeometryState) {
    for name in MediaVideoGeometryState.optionNames {
      if let option = value.options[name], mpv.setString("file-local-options/\(name)", option) < 0 {
        log("Failed to restore video geometry option \(name)", level: .warning)
      }
    }
    // Leave user/plugin/color filters outside IINA's geometry snapshot.
    var filters = mpv.getFilters(MPVProperty.vf).filter {
      !($0.label.map { videoGeometryFilterLabels.contains($0) } ?? false)
    }.map(\.stringFormat)
    for (index, filter) in value.filters.enumerated() {
      let position = index < value.filterIndices.count ? value.filterIndices[index] : filters.count
      filters.insert(filter, at: min(max(0, position), filters.count))
    }
    if mpv.setString("file-local-options/vf", filters.joined(separator: ",")) < 0 {
      log("Failed to restore video geometry filters", level: .warning)
    }
    syncVideoGeometryInfo(aspect: value.aspectDescription, crop: value.cropDescription)
  }

  private func syncVideoGeometryInfo(aspect: String = "Default", crop: String? = nil) {
    info.unsureAspect = MediaVideoGeometryState.aspectDescription(
      for: mpv.getDouble(MPVOption.Video.videoAspectOverride), preferred: aspect)
    info.rotation = mpv.getInt(MPVOption.Video.videoRotate)
    reloadSavedIINAfilters()
    if info.cropFilter != nil, let crop {
      info.unsureCrop = ["", "None"].contains(crop) ? "Custom" : crop
    }
  }

  private func restoreVideoTrackGeometryForCurrentMedia() {
    guard let url = videoGeometryMediaURL, let saved = videoGeometrySession[url] else { return }
    let available = Set(info.videoTracks.map(\.id))
    scopedTrackSettings.video = saved.video.filter { available.contains($0.key) }
    scopedTrackSettings.setTarget(available.contains(saved.videoTarget) ? saved.videoTarget : 0, for: .videoGeometry)
    info.videoTrackOrder = saved.videoOrder.filter { available.contains($0) }
    info.videoTrackOrder.append(contentsOf: info.videoTracks.map(\.id).filter { !info.videoTrackOrder.contains($0) })
    let video = saved.activeVideo.filter { available.contains($0) }
    if saved.activeVideo.isEmpty || !video.isEmpty {
      if !refreshTrackProcessing(.video, videoOverride: video) {
        scopedTrackSettings.video = [:]
        scopedTrackSettings.setTarget(0, for: .videoGeometry)
      }
    }
    postNotification(.iinaTrackSettingsChanged)
  }

  private func audioMixerInputsAreCompatible(_ inputs: Set<Int>) -> Bool {
    let tracks = info.audioTracks.filter { inputs.contains($0.id) }
    guard tracks.count == inputs.count, let first = tracks.first,
          let channels = first.demuxChannelCount, channels > 0,
          tracks.allSatisfy({ $0.demuxChannelCount == channels }) else { return false }
    return channels <= 2 || (first.demuxChannels != nil &&
      first.demuxChannels?.hasPrefix("unknown") == false &&
      tracks.allSatisfy({ $0.demuxChannels == first.demuxChannels }))
  }

  private func prepareAudioMixer() {
    guard info.currentURL?.isFileURL == true, info.audioTracks.count > 1,
          audioMixerInputsAreCompatible(Set(info.audioTracks.map(\.id))),
          ownedTrackGraph == nil,
          (mpv.getString(MPVOption.Miscellaneous.lavfiComplex) ?? "").isEmpty,
          (mpv.getString("audio-spdif") ?? "").isEmpty,
          let commands = mpv.getNode("command-list") as? [[String: Any]],
          commands.contains(where: {
            $0["name"] as? String == "lavfi-complex-command" &&
              ($0["args"] as? [[String: Any]])?.contains(where: { $0["name"] as? String == "refresh-audio" }) == true
          }) else { return }
    let selected = info.activeTrackIDs(.audio)
    persistentAudioInputs = Set(info.audioTracks.map(\.id))
    if !applyTrackSelection(audio: selected, video: info.layeredVideoTrackIDs,
                           changedType: .audio, soloID: selected.first ?? 0) {
      persistentAudioInputs = nil
    }
  }

  /// Only clear graphs installed by this player; custom lavfi graphs retain ownership.
  private func clearTrackGraphForNewFile() {
    if scopedCropPreview != nil {
      mainWindow?.interactiveMode.exit(discardingCrop: true)
      finishScopedCustomCrop(restoringSelection: false)
    }
    mainWindow?.finishVideoAspectTransition(restore: false)
    if let graph = ownedTrackGraph, mpv.getString(MPVOption.Miscellaneous.lavfiComplex) == graph {
      mpv.setString(MPVOption.Miscellaneous.lavfiComplex, "")
    }
    ownedTrackGraph = nil
    persistentAudioInputs = nil
    scopedTrackSettings = TrackProcessingState()
    postNotification(.iinaTrackSettingsChanged)
    info.mixedAudioTrackIDs = []
    info.layeredVideoTrackIDs = []
    info.videoTrackOrder = []
    info.audioTrackOrder = []
  }

  @discardableResult
  func setAudioTracks(_ ids: Set<Int>) -> Bool {
    guard info.state.active else { return false }
    reconcileTrackGraph()
    guard ids.isSubset(of: Set(info.audioTracks.map(\.id))) else { return false }
    return applyTrackSelection(audio: ids, video: info.layeredVideoTrackIDs,
                               changedType: .audio, soloID: ids.first ?? 0)
  }

  @discardableResult
  func setVideoTracks(_ ids: Set<Int>, order: [Int]? = nil) -> Bool {
    guard info.state.active, mainWindow?.interactiveMode.isActive != true else { return false }
    reconcileTrackGraph()
    let available = info.videoTracks.map(\.id)
    guard ids.isSubset(of: Set(available)) else { return false }
    var ordered = (order ?? info.videoTrackOrder).filter { available.contains($0) }
    ordered.append(contentsOf: available.filter { !ordered.contains($0) })
    let layers = ordered.filter { ids.contains($0) }
    let changesVideo = ids != info.activeTrackIDs(.video) ||
      (layers.count > 1 && layers != info.layeredVideoTrackIDs)
    if ids.isEmpty { mainWindow?.finishVideoAspectTransition() }
    if !changesVideo {
      info.videoTrackOrder = ordered
      return true
    }
    let startedTransition = !ids.isEmpty && changesVideo && mainWindow.beginVideoAspectTransition()
    guard applyTrackSelection(audio: info.activeTrackIDs(.audio), video: layers,
                              changedType: .video, soloID: ids.first ?? 0) else {
      if startedTransition { mainWindow.finishVideoAspectTransition() }
      return false
    }
    info.videoTrackOrder = ordered
    return true
  }

  /// Audio membership updates buffered audio without seeking video; topology rebuilds mpv's shared A/V graph.
  private func applyTrackSelection(audio: Set<Int>, video: [Int],
                                   changedType: MPVTrack.TrackType, soloID: Int, forceRebuild: Bool = false, audioRollback: [Int: AudioTrackProcessing]? = nil,
                                   excludingAudioInput: Int? = nil) -> Bool {
    var video = scopedCropPreview.map { [$0.id] } ?? video
    if changedType == .audio, video.isEmpty, !scopedTrackSettings.video.isEmpty {
      video = info.videoTrackOrder.filter { info.activeTrackIDs(.video).contains($0) }
      if video.isEmpty { video = info.activeTrackIDs(.video).sorted() }
    }
    let current = mpv.getString(MPVOption.Miscellaneous.lavfiComplex) ?? ""
    var inputs = persistentAudioInputs.map { $0.intersection(info.audioTracks.map(\.id)).union(audio) }
    if let excludingAudioInput { inputs?.remove(excludingAudioInput) }
    if let candidate = inputs, !audioMixerInputsAreCompatible(candidate) { inputs = nil }
    if !forceRebuild, changedType == .audio, let inputs, inputs == persistentAudioInputs,
       current == ownedTrackGraph {
      if audio == info.activeTrackIDs(.audio) { return true }
      var result: Int32 = -1
      mpv.command(MPVCommand("lavfi-complex-command"),
                  args: [AudioTrackMixGraph.target, "weights", AudioTrackMixGraph.weights(audio, inputs: inputs), "yes"],
                  checkError: false) { result = $0 }
      guard result >= 0 else {
        Utility.showAlert("track_graph_failed", sheetWindow: mainWindow.window)
        return false
      }
      info.mixedAudioTrackIDs = audio
      getSelectedTracks()
      aidChanged()
      return true
    }
    let audioGraph = ProcessedAudioGraph.make(audio, inputs: inputs, settings: scopedTrackSettings.audio,
                                             sampleRate: max(48000, info.audioTracks.compactMap(\.demuxSamplerate).max() ?? 48000))
    var videoGraph: String?
    if let preview = scopedCropPreview {
      videoGraph = "[vid\(preview.id)]null[vo]"
    } else if video.count > 1 || video.contains(where: { scopedTrackSettings.video[$0]?.isNeutral == false }) {
      guard let base = info.videoTracks.first(where: { $0.id == video.last }),
            let width = base.demuxW, let height = base.demuxH,
            let graph = ProcessedVideoGraph.make(video, width: width, height: height, settings: scopedTrackSettings.video, pixelAspect: base.demuxPixelAspect ?? 1) else {
        Utility.showAlert("video_layers_failed", sheetWindow: mainWindow.window)
        return false
      }
      videoGraph = graph
    }
    let nativeOption = changedType == .audio ? MPVOption.TrackSelection.aid : MPVOption.TrackSelection.vid
    if audioGraph == nil, videoGraph == nil, ownedTrackGraph == nil {
      mpv.setInt(nativeOption, soloID)
      getSelectedTracks()
      if changedType == .audio { aidChanged() } else { vidChanged() }
      return true
    }
    guard current.isEmpty || current == ownedTrackGraph else {
      Utility.showAlert("track_graph_conflict", sheetWindow: mainWindow.window)
      return false
    }
    let replacement = [audioGraph, videoGraph].compactMap { $0 }.joined(separator: ";")
    let previousAudio = info.activeTrackIDs(.audio)
    let previousVideo = info.activeTrackIDs(.video)
    let refreshVideo = mainWindow.loaded && (videoGraph != nil || !info.layeredVideoTrackIDs.isEmpty)
    if refreshVideo { mainWindow.videoView.displayActive() }
    defer {
      if refreshVideo, mpv.getFlag(MPVOption.PlaybackControl.pause) { mainWindow.videoView.displayIdle() }
    }
    if replacement != current {
      let result = mpv.setString(MPVOption.Miscellaneous.lavfiComplex, replacement)
      guard result >= 0 else {
        // Failed graph writes can destroy both outputs; runtime gains must be restored from weights, not option text.
        var restoration = current
        if ownedTrackGraph != nil, let end = current.range(of: "[ao]"),
           let graph = ProcessedAudioGraph.make(previousAudio, inputs: persistentAudioInputs, settings: audioRollback ?? scopedTrackSettings.audio, sampleRate: max(48000, info.audioTracks.compactMap(\.demuxSamplerate).max() ?? 48000)) {
          restoration = graph + current[end.upperBound...]
        }
        let restored = mpv.setString(MPVOption.Miscellaneous.lavfiComplex, restoration)
        let audioID = previousAudio.sorted().first ?? 0
        let videoID = info.layeredVideoTrackIDs.first ?? previousVideo.first ?? 0
        if restored < 0 {
          mainWindow?.finishVideoAspectTransition()
          ownedTrackGraph = nil
          persistentAudioInputs = nil
          info.mixedAudioTrackIDs = []
          info.layeredVideoTrackIDs = []
        }
        if restored >= 0 { ownedTrackGraph = restoration.isEmpty ? nil : restoration }
        if restored < 0 || !current.contains("[ao]"),
           mpv.getInt(MPVOption.TrackSelection.aid) != audioID {
          mpv.setInt(MPVOption.TrackSelection.aid, 0)
          mpv.setInt(MPVOption.TrackSelection.aid, audioID)
        }
        if restored < 0 || previousVideo.count <= 1,
           mpv.getInt(MPVOption.TrackSelection.vid) != videoID {
          mpv.setInt(MPVOption.TrackSelection.vid, 0)
          mpv.setInt(MPVOption.TrackSelection.vid, videoID)
        }
        if restored < 0 {
          getSelectedTracks()
          aidChanged()
          vidChanged()
        }
        Utility.showAlert("track_graph_failed", sheetWindow: mainWindow.window)
        return false
      }
    }
    ownedTrackGraph = replacement.isEmpty ? nil : replacement
    persistentAudioInputs = audioGraph == nil ? nil : inputs
    info.mixedAudioTrackIDs = audioGraph == nil ? [] : audio
    info.layeredVideoTrackIDs = videoGraph == nil ? [] : video
    // Replacing a graph can leave cached aid/vid equal to the requested native
    // choice with no track actually selected. Reset before selecting that ID.
    if audioGraph == nil {
      let id = changedType == .audio ? soloID : previousAudio.first ?? 0
      if mpv.getInt(MPVOption.TrackSelection.aid) != id {
        if id > 0 { mpv.setInt(MPVOption.TrackSelection.aid, 0) }
        mpv.setInt(MPVOption.TrackSelection.aid, id)
      }
    }
    if videoGraph == nil {
      let id = changedType == .video ? soloID : previousVideo.first ?? 0
      if mpv.getInt(MPVOption.TrackSelection.vid) != id {
        if id > 0 { mpv.setInt(MPVOption.TrackSelection.vid, 0) }
        mpv.setInt(MPVOption.TrackSelection.vid, id)
      }
    }
    getSelectedTracks()
    if changedType == .audio { aidChanged() } else { vidChanged() }
    return true
  }

  @discardableResult
  func refreshTrackProcessing(_ type: MPVTrack.TrackType, videoOverride: [Int]? = nil, audioRollback: [Int: AudioTrackProcessing]? = nil) -> Bool {
    let audio = info.activeTrackIDs(.audio)
    let activeVideo = info.activeTrackIDs(.video)
    var video = info.videoTrackOrder.filter { activeVideo.contains($0) }
    video.append(contentsOf: activeVideo.sorted().filter { !video.contains($0) })
    return applyTrackSelection(audio: audio, video: videoOverride ?? video, changedType: type,
                               soloID: type == .audio ? (audio.sorted().first ?? 0) : ((videoOverride ?? video).first ?? 0),
                               forceRebuild: true, audioRollback: audioRollback)
  }

  @discardableResult
  func refreshTrackAudioEQ(id: Int, previous: [Double], gains: [Double], audioRollback: [Int: AudioTrackProcessing]) -> Bool {
    let current = mpv.getString(MPVOption.Miscellaneous.lavfiComplex) ?? ""
    guard current == ownedTrackGraph,
          current.contains(ProcessedAudioGraph.equalizerTarget(trackID: id, band: 0)) else {
      return refreshTrackProcessing(.audio, audioRollback: audioRollback)
    }
    return sendTrackAudioEQCommands([(id, previous, gains)])
  }

  @discardableResult
  func neutralizeTrackAudioEQ(_ settings: [Int: AudioTrackProcessing], restoring: Bool = false) -> Bool {
    let current = mpv.getString(MPVOption.Miscellaneous.lavfiComplex) ?? ""
    guard ownedTrackGraph != nil else { return true }
    guard current == ownedTrackGraph else { return settings.isEmpty }
    let changes = settings.sorted(by: { $0.key < $1.key }).compactMap { id, value -> (Int, [Double], [Double])? in
      guard current.contains(ProcessedAudioGraph.equalizerTarget(trackID: id, band: 0)) else { return nil }
      let zero = Array(repeating: 0.0, count: 10)
      return restoring ? (id, zero, value.gains) : (id, value.gains, zero)
    }
    return sendTrackAudioEQCommands(changes)
  }

  private func sendTrackAudioEQCommands(_ changes: [(Int, [Double], [Double])]) -> Bool {
    let commands = changes.flatMap { id, previous, gains in
      gains.indices.filter { gains[$0] != previous[$0] }.map { (id, $0, previous[$0], gains[$0]) }
    }
    var applied: [(Int, Int, Double, Double)] = []
    for (index, command) in commands.enumerated() {
      let (id, band, old, gain) = command
      var result: Int32 = -1
      mpv.command(MPVCommand("lavfi-complex-command"),
        args: [ProcessedAudioGraph.equalizerTarget(trackID: id, band: band), "gain",
               String(gain), index == commands.count - 1 ? "yes" : "no"], checkError: false) { result = $0 }
      if result < 0 {
        for (oldID, oldBand, oldGain, _) in applied {
          mpv.command(MPVCommand("lavfi-complex-command"),
            args: [ProcessedAudioGraph.equalizerTarget(trackID: oldID, band: oldBand), "gain", String(oldGain), "yes"], checkError: false)
        }
        Utility.showAlert("track_graph_failed", sheetWindow: mainWindow.window)
        return false
      }
      applied.append((id, band, old, gain))
    }
    return true
  }

  /// Drop stale marks if a plugin or user has replaced our complete graph.
  private func reconcileTrackGraph() {
    if let graph = ownedTrackGraph, mpv.getString(MPVOption.Miscellaneous.lavfiComplex) != graph {
      ownedTrackGraph = nil
      persistentAudioInputs = nil
      info.mixedAudioTrackIDs = []
      info.layeredVideoTrackIDs = []
      getSelectedTracks()
      postNotification(.iinaAIDChanged)
      postNotification(.iinaVIDChanged)
    }
  }

  func cycleVideoTrack() {
    let tracks = info.orderedTrackList(.video)
    guard !tracks.isEmpty else { return }
    let selected = info.activeTrackIDs(.video)
    let current = selected.count == 1 ? selected.first : nil
    let next = tracks.firstIndex { $0.id == current }.map { ($0 + 1) % tracks.count } ?? 0
    setVideoTracks([tracks[next].id])
  }

  func cycleAudioTrack() {
    let tracks = info.orderedTrackList(.audio)
    guard !tracks.isEmpty else { return }
    let selected = info.activeTrackIDs(.audio)
    let current = selected.count == 1 ? selected.first : nil
    let next = tracks.firstIndex { $0.id == current }.map { ($0 + 1) % tracks.count } ?? 0
    setAudioTracks([tracks[next].id])
  }

  func setTrack(_ index: Int, forType: MPVTrack.TrackType) {
    guard info.state.active else { return }
    switch forType {
    case .audio:
      setAudioTracks(index > 0 ? [index] : [])
    case .video:
      setVideoTracks(index > 0 ? [index] : [])
    case .sub, .secondSub:
      let name = forType == .sub ? MPVOption.TrackSelection.sid : MPVOption.Subtitles.secondarySid
      let otherName = forType == .sub ? MPVOption.Subtitles.secondarySid : MPVOption.TrackSelection.sid
      // A source occupied by the other role is unavailable, never transferred.
      guard index <= 0 || mpv.getInt(otherName) != index else { return }
      mpv.setInt(name, index)
      getSelectedTracks()
      postNotification(.iinaSIDChanged)
    }
  }

  func setSpeed(_ speed: Double) {
    guard info.state.active else { return }
    let speed = max(AppData.mpvMinPlaybackSpeed, speed)
    mpv.setDouble(MPVOption.PlaybackControl.speed, speed)
  }

  func setVideoAspect(_ aspect: String) {
    guard info.state.active, mainWindow?.interactiveMode.isActive != true else { return }
    let retry: () -> Void = preservingOSDFeedbackOrigin { [weak self] in self?.setVideoAspect(aspect) }
    if mainWindow?.enqueueVideoGeometryChange(.aspect, request: retry) == true { return }
    mainWindow?.prepareVideoTransformWindowReference()
    let components = aspect.components(separatedBy: ":").compactMap(Double.init)
    let valid = Regex.aspect.matches(aspect) && components.count == 2 &&
      components.allSatisfy { $0.isFinite && $0 > 0 } && (components[0] / components[1]).isFinite
    let ratio = valid ? components[0] / components[1] : -1
    guard abs(mpv.getDouble(MPVOption.Video.videoAspectOverride) - ratio) > 0.000001 else {
      info.unsureAspect = valid ? aspect : "Default"; return
    }
    let apply = preservingOSDFeedbackOrigin { [weak self] () -> Bool in
      guard let self, mpv.setString(MPVOption.Video.videoAspectOverride, valid ? aspect : "-1") >= 0 else { return false }
      info.unsureAspect = valid ? aspect : "Default"
      return true
    }
    if let mainWindow { mainWindow.performVideoGeometryChange(.aspect, apply: apply) } else { _ = apply() }
  }

  func setVideoRotate(_ degree: Int) {
    guard info.state.active, mainWindow?.interactiveMode.isActive != true else { return }
    guard AppData.rotations.contains(degree) else { return }
    let retry: () -> Void = preservingOSDFeedbackOrigin { [weak self] in self?.setVideoRotate(degree) }
    if mainWindow?.enqueueVideoGeometryChange(.rotation, request: retry) == true { return }
    mainWindow?.prepareVideoTransformWindowReference()
    guard mpv.getInt(MPVOption.Video.videoRotate) != degree else { return }
    let apply = preservingOSDFeedbackOrigin { [weak self] () -> Bool in
      guard let self else { return false }
      return mpv.setString(MPVOption.Video.videoRotate, String(degree)) >= 0
    }
    if let mainWindow { mainWindow.performVideoGeometryChange(.rotation, apply: apply) } else { _ = apply() }
  }

  func setFlip(_ enable: Bool) {
    guard info.state.active, mainWindow?.interactiveMode.isActive != true else { return }
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
    guard info.state.active, mainWindow?.interactiveMode.isActive != true else { return }
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
    let value = String(describing: Preference.enum(for: .hardwareDecoder) as
                       Preference.HardwareDecoderOption)
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
    guard info.state.active, mainWindow?.interactiveMode.isActive != true else { return }
    mpv.command(.videoAdd, args: [url.mpvStr], checkError: false) { code in
      if code < 0 {
        self.log("Unsupported video: \(url.mpvStr)", level: .error)
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_video")
        }
      }
    }
  }

  func loadExternalAudioFile(_ url: URL) {
    guard info.state.active else { return }
    reconcileTrackGraph()
    let active = info.activeTrackIDs(.audio)
    let existing = Set(info.audioTracks.map(\.id))
    // Selection belongs to our graph owner, including while mixing sources.
    mpv.command(.audioAdd, args: [url.mpvStr, "auto"], checkError: false) { code in
      if code < 0 {
        self.log("Unsupported audio: \(url.mpvStr)", level: .error)
        DispatchQueue.main.async {
          Utility.showAlert("unsupported_audio")
        }
        return
      }
      self.getTrackInfo()
      let added = Set(self.info.audioTracks.map(\.id)).subtracting(existing)
      if !added.isEmpty { self.setAudioTracks(active.union(added)) }
      self.postNotification(.iinaTracklistChanged)
    }
  }

  @discardableResult
  func removeExternalTrack(_ id: Int, type: MPVTrack.TrackType, order: [Int]) -> Bool {
    guard info.state.active, type == .audio || type == .video,
          info.trackList(type).contains(where: { $0.id == id && $0.isExternal }),
          type != .video || !mainWindow.interactiveMode.isActive else { return false }
    reconcileTrackGraph()
    let graph = mpv.getString(MPVOption.Miscellaneous.lavfiComplex) ?? ""
    guard graph.isEmpty || graph == ownedTrackGraph else {
      Utility.showAlert("track_graph_conflict", sheetWindow: mainWindow.window)
      return false
    }
    let available = info.trackList(type).map(\.id)
    var ordered = order.filter { available.contains($0) }
    ordered.append(contentsOf: available.filter { !ordered.contains($0) })
    let active = info.activeTrackIDs(type)
    let remaining = TrackSelectionState.selectionAfterRemoving(id, order: ordered, active: active)
    let previousAudio = info.activeTrackIDs(.audio)
    let previousVideo = info.activeTrackIDs(.video)
    var videoOrder = (type == .video ? ordered : info.videoTrackOrder).filter { previousVideo.contains($0) }
    videoOrder.append(contentsOf: previousVideo.sorted().filter { !videoOrder.contains($0) })
    let oldInputs = persistentAudioInputs
    let reconnect = active.contains(id) || (type == .audio && oldInputs?.contains(id) == true)
    let startedTransition = type == .video && active.contains(id) && !remaining.isEmpty && mainWindow.beginVideoAspectTransition()
    if reconnect, !applyTrackSelection(
      audio: type == .audio ? remaining : previousAudio,
      video: type == .video ? ordered.filter { remaining.contains($0) } : videoOrder,
      changedType: type, soloID: remaining.sorted().first ?? 0, forceRebuild: true,
      excludingAudioInput: type == .audio ? id : nil
    ) {
      if startedTransition { mainWindow.finishVideoAspectTransition() }
      return false
    }
    var result: Int32 = -1
    mpv.command(type == .audio ? .audioRemove : .videoRemove, args: [String(id)], checkError: false) { result = $0 }
    getTrackInfo()
    // mpv can report command success even if a connected input was not removed.
    guard result >= 0, !info.trackList(type).contains(where: { $0.id == id }) else {
      if reconnect {
        persistentAudioInputs = oldInputs
        _ = applyTrackSelection(audio: previousAudio, video: videoOrder, changedType: type,
                               soloID: active.sorted().first ?? 0, forceRebuild: true)
      }
      if startedTransition { mainWindow.finishVideoAspectTransition() }
      Utility.showAlert("track.remove_failed", sheetWindow: mainWindow.window)
      return false
    }
    if type == .audio { scopedTrackSettings.audio.removeValue(forKey: id) }
    else {
      scopedTrackSettings.video.removeValue(forKey: id)
      info.videoTrackOrder.removeAll { $0 == id }
    }
    let editingGroup: TrackSettingsGroup = type == .audio ? .audioDelay : .videoGeometry
    if scopedTrackSettings.target(editingGroup) == id { scopedTrackSettings.setTarget(0, for: editingGroup) }
    trackListChanged()
    postNotification(.iinaTrackSettingsChanged)
    return true
  }

  /// Shows the Font Chooser window to select a new font for the player
  func chooseSubFont(forPrimary: Bool = true) {
    guard info.state.active else { return }
    let subFont = mpv.getString(SubtitleStyle.option(MPVOption.Subtitles.subFont, forPrimary: forPrimary))
    Utility.quickFontPickerWindow(selecting: subFont) { [self] result in
      if let result {
        setSubFont(result, forPrimary: forPrimary)
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

  func loadExternalSubFile(_ url: URL, delay: Bool = false, suppressError: Bool = false) {
    guard info.state.active else { return }
    var track: MPVTrack?
    info.$subTracks.withLock { track = $0.first(where: { $0.externalFilename == url.mpvStr }) }
    if let track {
      mpv.command(.subReload, args: [String(track.id)], checkError: false)
      return
    }

    mpv.command(.subAdd, args: [url.mpvStr], checkError: false, level: .verbose) { code in
      if code < 0 {
        self.log("Unsupported sub: \(url.mpvStr)", level: .error)
        // only show alert when the subtitle is added manually
        guard !suppressError else { return }
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
  }

  func setAudioDelay(_ delay: Double) {
    guard info.state.active else { return }
    mpv.setDouble(MPVOption.Audio.audioDelay, delay)
  }

  func setSubDelay(_ delay: Double, forPrimary: Bool = true) {
    guard info.state.active else { return }
    let option = forPrimary ? MPVOption.Subtitles.subDelay : MPVOption.Subtitles.secondarySubDelay
    mpv.setDouble(option, delay)
  }

  func appendToPlaylist(_ path: String, silent: Bool = false) {
    mpv.playlistAppend(path)
    info.isShuffled = false
    if !silent {
      postNotification(.iinaPlaylistChanged)
    }
  }

  func playlistMove(_ from: Int, to: Int) {
    mpv.playlistMove(from, to: to)
    info.isShuffled = false
    postNotification(.iinaPlaylistChanged)
  }

  func playlistReorder(newPlaylist: [MPVPlaylistItem]) {
    guard Set(info.playlist) == Set(newPlaylist) else { return }
    if info.playlist == newPlaylist { return }
    info.isShuffled = false
    mpv.command(.playlistClear)
    guard let currentPlaying = newPlaylist.firstIndex(where: { $0.isPlaying } ) else {
      for item in newPlaylist {
        mpv.playlistAppend(item.filename)
      }
      return
    }

    for i in (0..<currentPlaying).reversed() {
      mpv.playlistInsert(newPlaylist[i].filename, index: 0)
    }
    for i in currentPlaying + 1..<newPlaylist.count {
      mpv.playlistAppend(newPlaylist[i].filename)
    }

    postNotification(.iinaPlaylistChanged)
  }

  func addToPlaylist(paths: [String], at index: Int = -1) {
    getPlaylist()
    info.isShuffled = false
    for path in paths {
      mpv.playlistAppend(path)
    }
    let previousCount = info.$playlist.withLock { $0.count }
    if index <= previousCount && index >= 0 {
      for i in 0..<paths.count {
        playlistMove(previousCount + i, to: index + i)
      }
    }
    postNotification(.iinaPlaylistChanged)
  }

  func playlistRemove(_ index: Int) {
    mpv.playlistRemove(index)
    info.isShuffled = false
    postNotification(.iinaPlaylistChanged)
  }

  func playlistRemove(_ indexSet: IndexSet) {
    guard !indexSet.isEmpty else { return }
    var count = 0
    for i in indexSet {
      mpv.playlistRemove(i - count)
      count += 1
    }
    info.isShuffled = false
    postNotification(.iinaPlaylistChanged)
  }

  func clearPlaylist() {
    mpv.command(.playlistClear)
    info.isShuffled = false
    postNotification(.iinaPlaylistChanged)
  }

  /// Play the entry at the given position in the playlist.
  /// - Important: This method will ensure playback is paused before changing the position in the playlist. If playback is not
  ///     paused, audio can start playing before video is shown. This is most noticeable with high resolution videos encoded with
  ///     newer high compression codecs (such as AV1), when running on older Macs that lack support for hardware decoding of the
  ///     codec used. Playback will be started once the video has been loaded and the size of the video is known (unless the "Pause"
  ///     setting is enabled under "When media is opened"). Playback is only paused when the user manually changes the position in
  ///     the playlist in order to not disrupt gapless audio.
  /// - Important: Although primary responsibility for ensuring the display link is running when playback is in progress belongs to
  ///     the `pauseChanged` method, this method calls `displayActive` to provide more time for the display link to start up
  ///     expecting that normally playback will be resumed by `notifyWindowVideoSizeChanged` once the file is loaded. Note
  ///     that when this method pauses playback `pauseChanged` will call `displayIdle`. That is not a problem as that method
  ///     does not immediately stop the display link. The link will still be running when `notifyWindowVideoSizeChanged`
  ///     resumes playback.
  /// - Important: The mpv
  ///     [playlist-play-index](https://mpv.io/manual/stable/#command-interface-playlist-play-index)
  ///     playlist manipulation command is intentionally used instead of setting the mpv
  ///     [playlist-pos](https://mpv.io/manual/stable/#command-interface-playlist-pos) property so that double
  ///     clicking in the playlist on the entry that is currently playing reloads that entry.
  /// - Parameter pos: Position of the entry in the playlist to be played.
  func playFileInPlaylist(_ pos: Int) {
    mainWindow.videoView.displayActive()
    if !mpv.getFlag(MPVOption.PlaybackControl.pause) {
      log("Pausing playback before playing entry at index \(pos) in the playlist")
      mpv.setFlag(MPVOption.PlaybackControl.pause, true, level: .verbose)
    }
    mpv.command(.playlistPlayIndex, args: [String(pos)], level: .verbose)
    getPlaylist()
  }

  /// Play the next or the previous entry in the playlist.
  /// - Important: This method will ensure playback is paused before changing the position in the playlist. If playback is not
  ///     paused, audio can start playing before video is shown. This is most noticeable with high resolution videos encoded with
  ///     newer high compression codecs (such as AV1), when running on older Macs that lack support for hardware decoding of the
  ///     codec used. Playback will be started once the video has been loaded and the size of the video is known (unless the "Pause"
  ///     setting is enabled under "When media is opened"). Playback is only paused when the user manually changes the position in
  ///     the playlist in order to not disrupt gapless audio.
  /// - Important: Although primary responsibility for ensuring the display link is running when playback is in progress belongs to
  ///     the `pauseChanged` method, this method calls `displayActive` to provide more time for the display link to start up
  ///     expecting that normally playback will be resumed by `notifyWindowVideoSizeChanged` once the file is loaded. Note
  ///     that when this method pauses playback `pauseChanged` will call `displayIdle`. That is not a problem as that method
  ///     does not immediately stop the display link. The link will still be running when `notifyWindowVideoSizeChanged`
  ///     resumes playback.
  /// - Parameter nextMedia: When `true` play the next entry in the playlist; otherwise play the previous entry.
  func navigateInPlaylist(nextMedia: Bool) {
    guard !mainWindow.interactiveMode.isActive else { return }

    if nextMedia == false && (info.playlist.first?.isPlaying) ?? false {
      seek(absoluteSecond: 0)
    } else {
      mainWindow.videoView.displayActive()
      if !mpv.getFlag(MPVOption.PlaybackControl.pause) {
        log("Pausing playback before playing \(nextMedia ? "next" : "previous") entry in playlist")
        mpv.setFlag(MPVOption.PlaybackControl.pause, true, level: .verbose)
      }
      mpv.command(nextMedia ? .playlistNext : .playlistPrev, checkError: false)
    }
  }

  @discardableResult
  func playChapter(_ pos: Int) -> MPVChapter? {
    guard info.state.active else { return nil }
    log("Seeking to chapter \(pos)", level: .verbose)
    let chapters = info.chapters
    guard pos >= 0, pos < chapters.count else {
      return nil
    }
    userInitiatedSeek()
    let chapter = chapters[pos]
    mpv.command(.seek, args: ["\(chapter.time.second)", "absolute"])
    resume()
    // need to update time pos
    syncUITime()
    return chapter
  }

  func setCrop(fromString str: String) {
    guard info.state.active, mainWindow?.interactiveMode.isActive != true else { return }
    mainWindow?.prepareVideoTransformWindowReference()
    if let aspect = Aspect(string: str) {
      // Match Custom Crop's rotated output coordinates; file metadata may describe another video track.
      let geometry = interactiveVideoGeometry(uncropped: true)
      guard geometry.sourceSize.width > 0, geometry.sourceSize.height > 0,
            aspect.value.isFinite, aspect.value > 0,
            geometry.pixelAspectRatio.isFinite, geometry.pixelAspectRatio > 0 else { return }
      let pixelAspect = Aspect(size: NSSize(width: aspect.value / geometry.pixelAspectRatio, height: 1))
      let size = geometry.selectionSize.crop(withAspect: pixelAspect)
      let selection = size.centeredRect(in: NSRect(origin: .zero, size: geometry.selectionSize))
      let cropped = geometry.filterRect(for: selection)
      guard cropped.width >= 1, cropped.height >= 1 else { return }
      let vf = MPVFilter.crop(w: Int(cropped.width), h: Int(cropped.height),
                              x: Int(cropped.minX), y: Int(cropped.minY), exact: true)
      vf.label = Constants.FilterName.crop
      applyCropChange(vf, description: str, outputSize: NSSize(width: Int(cropped.width), height: Int(cropped.height)))
    } else {
      applyCropChange(nil, description: "None", outputSize: nil)
    }
  }

  private func applyCropChange(_ filter: MPVFilter?, description: String, outputSize: NSSize?) {
    let apply = preservingOSDFeedbackOrigin { [weak self] in
      guard let self else { return }
      if let filter {
        if setCrop(fromFilter: filter) { info.unsureCrop = description }
      } else {
        removeCropFilter()
      }
      postNotification(.iinaTrackSettingsChanged)
    }
    let size = outputSize ?? interactiveVideoGeometry(uncropped: true).sourceSize
    let current = NSSize(width: mpv.getInt(MPVProperty.videoOutParams + "/w"),
                         height: mpv.getInt(MPVProperty.videoOutParams + "/h"))
    let labels = [Constants.FilterName.crop, Constants.FilterName.flip, Constants.FilterName.mirror]
    let graph = mpv.getString("lavfi-complex") ?? ""
    // The persistent audio mixer does not change video geometry or readiness.
    let hasIndependentVideo = graph.isEmpty || graph == ownedTrackGraph && !graph.contains("[vo]")
    // Size-preserving graphs have no output-size event to release this bridge.
    if size != current || mainWindow?.isPlayerCropTransitionInProgress == true, size.width > 0, size.height > 0,
       mpv.getFilters(MPVProperty.vf).allSatisfy({ $0.label.map(labels.contains) == true }),
       hasIndependentVideo,
       mainWindow?.prepareCropChange(apply,
         selection: cropTransitionSelection(filter), displaySize: cropTransitionDisplaySize(filter),
         filterRect: cropTransitionFilterRect(filter)) == true { return }
    if mainWindow?.isPlayerCropTransitionInProgress == true { mainWindow?.cancelCropExitTransition() }
    apply()
  }

  var canAnimateCropSource: Bool {
    let graph = mpv.getString("lavfi-complex") ?? ""
    let centered = ["video-zoom", "video-pan-x", "video-pan-y", "panscan", "video-rotate",
                    "video-align-x", "video-align-y", "video-margin-ratio-left", "video-margin-ratio-right",
                    "video-margin-ratio-top", "video-margin-ratio-bottom"].allSatisfy { abs(mpv.getDouble($0)) < 0.000001 }
    return centered && mpv.getDouble("video-aspect-override") <= 0
      && abs(mpv.getDouble("video-scale-x") - 1) < 0.000001 && abs(mpv.getDouble("video-scale-y") - 1) < 0.000001
      && (mpv.getString("video-crop") ?? "").isEmpty && (mpv.getString("video-unscaled") ?? "no") == "no"
      && mpv.getFilters(MPVProperty.vf).allSatisfy { $0.label == Constants.FilterName.crop }
      && (graph.isEmpty || graph == ownedTrackGraph && !graph.contains("[vo]"))
  }

  /// Aspect and quarter-turn transitions compensate the current output geometry,
  /// so an existing aspect override or rotation is a valid starting point.
  var canAnimateVideoGeometry: Bool {
    let graph = mpv.getString("lavfi-complex") ?? ""
    let centered = ["video-zoom", "video-pan-x", "video-pan-y", "panscan",
                    "video-align-x", "video-align-y", "video-margin-ratio-left", "video-margin-ratio-right",
                    "video-margin-ratio-top", "video-margin-ratio-bottom"].allSatisfy { abs(mpv.getDouble($0)) < 0.000001 }
    return centered && [0, 90, 180, 270].contains(mpv.getInt(MPVOption.Video.videoRotate))
      && abs(mpv.getDouble("video-scale-x") - 1) < 0.000001 && abs(mpv.getDouble("video-scale-y") - 1) < 0.000001
      && (mpv.getString("video-crop") ?? "").isEmpty && (mpv.getString("video-unscaled") ?? "no") == "no"
      && mpv.getFilters(MPVProperty.vf).allSatisfy { $0.label == Constants.FilterName.crop }
      && (graph.isEmpty || graph == ownedTrackGraph && !graph.contains("[vo]"))
  }

  var defaultVideoPixelAspect: Double {
    let container = info.videoTracks.first { $0.id == info.vid }?.demuxPixelAspect ?? 0
    let decoded = mpv.getDouble("video-dec-params/par")
    return container.isFinite && container > 0 ? container : decoded.isFinite && decoded > 0 ? decoded : 1
  }

  var defaultVideoRotation: Int {
    let decoded = mpv.getInt("video-dec-params/rotate")
    if decoded != 0 { return decoded }
    let tracks = mpv.getNode(MPVProperty.trackList) as? [[String: Any]] ?? []
    return tracks.first { $0["type"] as? String == "video" && $0["id"] as? Int == info.vid }?["demux-rotation"] as? Int ?? 0
  }

  func cropTransitionFrame(in bounds: NSRect) -> CropTransitionOverlay.PlayerFrame? {
    // These options move pixels independently of the crop's source coordinates.
    guard canAnimateCropSource, !bounds.isEmpty, info.flipFilter == nil, info.mirrorFilter == nil,
          [MPVOption.Video.videoZoom, MPVOption.Video.videoPanX, MPVOption.Video.videoPanY,
           MPVOption.Video.panscan, MPVOption.Video.videoRotate].allSatisfy({ abs(mpv.getDouble($0)) < 0.000001 }),
          mpv.getDouble(MPVOption.Video.videoAspectOverride) <= 0 else { return nil }
    let geometry = interactiveVideoGeometry(uncropped: true)
    let display = interactiveVideoGeometry(uncropped: false).displaySize
    guard geometry.selectionSize.width > 0, geometry.selectionSize.height > 0,
          display.width > 0, display.height > 0,
          [0, 90, 180, 270].contains(geometry.rotation) else { return nil }
    let normalized = cropTransitionSelection(info.cropFilter)
    guard !normalized.isEmpty else { return nil }
    return CropTransitionOverlay.PlayerFrame(selection: normalized,
                                             videoRect: CropTransitionOverlay.fit(display, in: bounds), viewport: bounds)
  }

  private func cropTransitionSelection(_ filter: MPVFilter?) -> NSRect {
    let geometry = interactiveVideoGeometry(uncropped: true)
    let rect = cropTransitionFilterRect(filter)
    guard !rect.isEmpty, NSRect(origin: .zero, size: geometry.sourceSize).contains(rect),
          geometry.selectionSize.width > 0, geometry.selectionSize.height > 0 else { return .zero }
    let selected = geometry.selectionRect(forFilterRect: rect)
    return NSRect(x: selected.minX / geometry.selectionSize.width,
                  y: selected.minY / geometry.selectionSize.height,
                  width: selected.width / geometry.selectionSize.width,
                  height: selected.height / geometry.selectionSize.height)
  }

  private func cropTransitionDisplaySize(_ filter: MPVFilter?) -> NSSize {
    let geometry = interactiveVideoGeometry(uncropped: true)
    let selected = cropTransitionSelection(filter)
    return NSSize(width: selected.width * geometry.displaySize.width,
                  height: selected.height * geometry.displaySize.height)
  }

  private func cropTransitionFilterRect(_ filter: MPVFilter?) -> NSRect {
    let size = interactiveVideoGeometry(uncropped: true).sourceSize
    guard let filter else { return NSRect(origin: .zero, size: size) }
    guard let params = filter.params, let width = params["w"].flatMap(Int.init),
          let height = params["h"].flatMap(Int.init), width > 0, height > 0 else { return .zero }
    return NSRect(x: params["x"].flatMap(Int.init) ?? Int((size.width - CGFloat(width)) / 2),
                  y: params["y"].flatMap(Int.init) ?? Int((size.height - CGFloat(height)) / 2),
                  width: width, height: height)
  }

  @discardableResult
  func setCrop(fromFilter filter: MPVFilter) -> Bool {
    filter.label = Constants.FilterName.crop
    beginPausedCropRefresh()
    guard addVideoFilter(filter) else { finishPausedCropRefresh(); return false }
    info.cropFilter = filter
    info.unsureCrop = "Custom"
    return true
  }

  /// Remove the crop filter managed by IINA.
  func removeCropFilter() {
    mainWindow?.prepareVideoTransformWindowReference()
    if let vf = info.cropFilter {
      beginPausedCropRefresh()
      if removeVideoFilter(vf) {
        info.cropFilter = nil
        info.unsureCrop = "None"
      } else {
        finishPausedCropRefresh()
      }
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

  /// Return the list of audio devices.
  ///
  /// This function obtains the list of audio devices from mpv using the
  /// [audio-device-list](https://mpv.io/manual/stable/#command-interface-audio-device-list) property. It then
  /// filters out audio devices that are not applicable based on the current IINA audio output driver setting
  /// (`audioDriverEnableAVFoundation`) and returns the results as a list of `MPVAudioDevice` objects.
  ///
  /// A mpv audio device is tied to a specific audio output driver (with the exception of the `auto` pseudo device). Thus an individual
  /// audio device appears twice in the list, once for the `coreaudio` driver and once for the `avfoundation` driver. This allows
  /// you to select both an audio device and a driver at the same time when setting the
  /// [--audio-device](https://mpv.io/manual/stable/#options-audio-device) mpv option. The documentation for
  /// [--audio-device](https://mpv.io/manual/stable/#options-audio-device) contains this caution:
  /// ```
  /// However, the --ao option will strictly force a specific AO. To avoid confusion, don't use --ao
  /// and --audio-device together.
  /// ```
  /// What the manual means by confusion is that if [--ao](https://mpv.io/manual/stable/#audio-output-drivers-ao)
  /// has been set to a specific audio output driver and
  /// [--audio-device](https://mpv.io/manual/stable/#options-audio-device) is then set to an audio device for a
  /// driver that is not contained in the list of drivers specified by
  /// [--ao](https://mpv.io/manual/stable/#audio-output-drivers-ao) then mpv will not be able to use that audio
  /// device and will fall back to the default audio device.
  ///
  /// IINA sets [--ao](https://mpv.io/manual/stable/#audio-output-drivers-ao) to either `coreaudio` or
  /// `avfoundation` based on the IINA `audioDriverEnableAVFoundation` setting. This is intentional as the
  /// `avfoundation` driver is experimental and has some problems that still need to be resolved. We want the user to explicitly
  /// choose to use the `avfoundation` driver, not accidentally choose it when selecting an audio output device.
  ///
  /// The [audio-device-list](https://mpv.io/manual/stable/#command-interface-audio-device-list) property
  /// returns the full list of audio devices regardless of the
  /// [--ao](https://mpv.io/manual/stable/#audio-output-drivers-ao) setting. Thus IINA must filter the list and
  /// remove audio devices tied to an audio output device that is not configured in
  /// [--ao](https://mpv.io/manual/stable/#audio-output-drivers-ao).
  /// - Returns: An array of `MPVAudioDevice` objects  that identify the available audio devices.
  func getAudioDevices() -> [MPVAudioDevice] {
    let raw = mpv.getNode(MPVProperty.audioDeviceList)
    guard let list = raw as? [[String: String]] else { return [] }
    let ignore = Preference.bool(for: .audioDriverEnableAVFoundation) ? "coreaudio" : "avfoundation"
    var result: [MPVAudioDevice] = []
    for dict in list {
      let device = MPVAudioDevice(dict)
      guard device.driver != ignore else {
        log("Ignored audio device due to audio driver setting:\n \(device)", level: .verbose)
        continue
      }
      result.append(device)
    }
    return result
  }

  func setAudioDevice(_ name: String) {
    mpv.setString(MPVProperty.audioDevice, name)
  }

  /** Scale is a double value in [-100, -1] + [1, 100] */
  func setSubScale(_ scale: Double, forPrimary: Bool = true) {
    mpv.setDouble(SubtitleStyle.option(MPVOption.Subtitles.subScale, forPrimary: forPrimary),
                  abs(scale), level: .verbose)
  }

  func setSubPos(_ pos: Int, forPrimary: Bool = true) {
    let option = forPrimary ? MPVOption.Subtitles.subPos : MPVOption.Subtitles.secondarySubPos
    mpv.setInt(option, pos, level: .verbose)
  }

  func resetSubtitleStyle(forPrimary: Bool = true) {
    // Reset to saved startup style; factory defaults would change previously untouched subtitles.
    setSubScale(1, forPrimary: forPrimary)
    setSubFont(Preference.string(for: .subTextFont)!, forPrimary: forPrimary)
    setSubTextSize(Double(Preference.float(for: .subTextSize)), forPrimary: forPrimary)
    setSubTextColor(Preference.string(for: .subTextColorString)!, forPrimary: forPrimary)
    setSubTextBorderSize(Double(Preference.float(for: .subBorderSize)), forPrimary: forPrimary)
    setSubTextBorderColor(Preference.string(for: .subBorderColorString)!, forPrimary: forPrimary)
    setSubTextBgColor(Preference.string(for: .subShadowColorString)!, forPrimary: forPrimary)
  }

  func setSubTextColor(_ colorString: String, forPrimary: Bool = true) {
    mpv.setString("options/" + SubtitleStyle.option(MPVOption.Subtitles.subColor, forPrimary: forPrimary), colorString)
  }

  func setSubTextSize(_ size: Double, forPrimary: Bool = true) {
    mpv.setDouble("options/" + SubtitleStyle.option(MPVOption.Subtitles.subFontSize, forPrimary: forPrimary), size)
  }

  func setSubTextBold(_ bold: Bool) {
    mpv.setFlag("options/" + MPVOption.Subtitles.subBold, bold)
  }

  func setSubTextBorderColor(_ colorString: String, forPrimary: Bool = true) {
    mpv.setString("options/" + SubtitleStyle.option(MPVOption.Subtitles.subOutlineColor, forPrimary: forPrimary), colorString)
  }

  func setSubTextBorderSize(_ size: Double, forPrimary: Bool = true) {
    mpv.setDouble("options/" + SubtitleStyle.option(MPVOption.Subtitles.subOutlineSize, forPrimary: forPrimary), size)
  }

  func setSubTextBgColor(_ colorString: String, forPrimary: Bool = true) {
    mpv.setString("options/" + SubtitleStyle.option(MPVOption.Subtitles.subBackColor, forPrimary: forPrimary), colorString)
  }

  func setSubEncoding(_ encoding: String) {
    mpv.setString(MPVOption.Subtitles.subCodepage, encoding)
    info.subEncoding = encoding
  }

  func setSubFont(_ font: String, forPrimary: Bool = true) {
    mpv.setString(SubtitleStyle.option(MPVOption.Subtitles.subFont, forPrimary: forPrimary), font)
    postNotification(.iinaSubFontChanged)
  }

  func savePlaybackPosition() {
    guard mpv.getFlag(MPVOption.WatchLater.savePositionOnQuit) else { return }

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
        info.isShuffled = true
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
    cancelVideoGeometryOSDRefresh()
    cancelScreenshotRequests()
    pausedCropRefresh = nil
    mainWindow?.cancelCropExitTransition()
    guard info.state.active else { return }
    log("File started")

    Task { @MainActor in
      mainWindow.liveText.clearAnalysis()
    }

    MemoryUsage.shared.logUsage("after file started")
    info.trackSelectionGeneration += 1
    info.justStartedFile = true
    info.disableOSDForFileLoading = true

    info.currentURL = path.contains("://") ?
      URL(string: path.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? path) :
      URL(fileURLWithPath: path)
    if let url = info.currentURL {
      info.mpvMd5 = Utility.mpvWatchLaterMd5(url, ignorePathInWatchLaterConfig)
    }
    info.isNetworkResource = !info.currentURL!.isFileURL

    // set "date last opened" attribute
    if let url = info.currentURL, url.isFileURL {
      let time = Date().timeIntervalSince1970
      // Data mimics timespec struct
      let ts = [UInt64(time), UInt64(time.truncatingRemainder(dividingBy: 1) * 1_000_000_000)]
      let data = Data(bytesOf: ts)
      // set the attribute; the key is undocumented
      let name = "com.apple.lastuseddate#PS"
      url.withUnsafeFileSystemRepresentation { fileSystemPath in
        let _ = data.withUnsafeBytes {
          setxattr(fileSystemPath, name, $0.baseAddress, data.count, 0, 0)
        }
      }
    }

    NowPlayingInfoManager.shared.updateInfo(withTitle: true)

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
          var loadedSubs = Set<URL>()
          for sub in matchedSubs {
            // filter duplicated matched subtitles, see https://github.com/iina/iina/issues/5399
            guard !loadedSubs.contains(sub) else { continue }
            loadedSubs.insert(sub)
            try checkTicket(currentTicket)
            loadExternalSubFile(sub, suppressError: true)
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

    info.state = .loaded

    // Must force drawing to cover the case where this player was previously used to play a video
    // and is now playing an audio file without an album cover and without using music mode.
    // See issue #5403.
    mainWindow.forceDraw("file loaded", always: true)

    // Get video size and set the initial window size
    let width = mpv.getInt(MPVProperty.width)
    let height = mpv.getInt(MPVProperty.height)
    let duration = mpv.getDouble(MPVProperty.duration)
    let pos = mpv.getDouble(MPVProperty.timePos)
    let remaining = Preference.bool(for: .scaleRemainingTime) ?
      mpv.getDouble(MPVProperty.playtimeRemainingFull) :
      mpv.getDouble(MPVProperty.timeRemainingFull)
    info.videoHeight = height
    info.videoWidth = width
    info.displayWidth = 0
    info.displayHeight = 0
    info.videoDuration = VideoTime(duration)
    if let filename = mpv.getString(MPVProperty.path) {
      info.setCachedVideoDuration(filename, duration)
    }
    info.videoPosition = VideoTime(pos)
    info.videoRemaining = VideoTime(remaining)
    triedUsingExactSeekForCurrentFile = false
    checkUnsyncedWindowOptions()
    // generate thumbnails if window has loaded video
    if mainWindow.isVideoLoaded {
      generateThumbnails()
    }
    // call `trackListChanged` to load tracks and check whether need to switch to music mode
    trackListChanged()
    restoreVideoTrackGeometryForCurrentMedia()
    prepareAudioMixer()
    videoGeometryIsLoaded = true
    getPlaylist()
    getChapters()
    syncAbLoop()
    refreshSyncUITimer()
    touchBarSupport.setupTouchBarUI()

    // Workaround mpv issue #18581 / IINA issue #6378. Newer iPhones can generate video files with
    // two audio tracks, one encoded with the Apple Positional Audio Codec to support spatial audio
    // and one stereo track. FFmpeg 9.0.2 does not support APAC (FFmpeg is adding support). If the
    // APAC encoded track happens to be the first audio track, mpv will select it, fail to decode it
    // and continue playback with no sound. Select the second track if this has occurred.
    if info.aid == 0, info.audioTracks.count >= 2, info.audioTracks[0].codec == "apple_apac" {
      log("""
        Audio track 1 uses Apple Positional Audio Codec, switching to audio track 2:
        \(info.audioTracks.compactMap { String(describing: $0) }.joined(separator: "\n"))
        """, level: .warning)
      setTrack(2, forType: .audio)
    }

    if info.activeTrackIDs(.audio).isEmpty {
      mainWindow.muteButton.isHidden = true
      mainWindow.volumeSlider.isHidden = true
    }

    if info.vid == 0 {
      notifyWindowVideoSizeChanged()
    }

    if self.isInMiniPlayer {
      miniPlayer.refreshArtworkVisibility()
      miniPlayer.handleVideoSizeChange()
    }

    // add to history
    if let url = info.currentURL {
      let duration = info.videoDuration ?? .zero
      let mediaTitle = mpv.getString(MPVProperty.mediaTitle)
      // Unfortunately the mpv media-title property returns the filename when there isn't a title.
      // Don't store a title unless the media actually has one.
      let titleToUse: String? = {
        guard let mediaTitle else { return nil }
        guard mediaTitle != url.lastPathComponent else { return nil }
        return mediaTitle
      }()
      HistoryController.shared.add(url, duration: duration.second, title: titleToUse,
                                   ignorePathInWatchLaterConfig)
      if Preference.bool(for: .recordRecentFiles) && Preference.bool(for: .trackAllFilesInRecentOpenMenu) {
        AppDelegate.shared.noteNewRecentDocumentURL(url)
      }
    }
    postNotification(.iinaFileLoaded)
    events.emit(.fileLoaded, data: info.currentURL?.absoluteString ?? "")

    Task { @MainActor in
      mainWindow.liveText.requestAnalysis()
    }
  }

  func fileEnded(_ dueToStopCommand: Bool) {
    cancelVideoGeometryOSDRefresh()
    pausedCropRefresh = nil
    // if receive end-file when loading file, might be error
    // wait for idle
    if info.state == .loading || info.state == .starting {
      if !dueToStopCommand {
        receivedEndFileWhileLoading = true
      }
    } else {
      info.shouldAutoLoadFiles = false
    }
    MemoryUsage.shared.logUsage("after file ended")
  }

  func afChanged() {
    guard info.state.active else { return }
    postNotification(.iinaAFChanged)
  }

  func aidChanged() {
    guard info.state.active else { return }
    info.aid = (info.mixedAudioTrackIDs.count == 1 ? info.mixedAudioTrackIDs.first : nil) ??
      mpv.getInt(MPVOption.TrackSelection.aid)
    guard mainWindow.loaded else { return }
    reconcileTrackGraph()
    let hasAudio = !info.activeTrackIDs(.audio).isEmpty
    mainWindow?.muteButton.isHidden = !hasAudio
    mainWindow?.volumeSlider.isHidden = !hasAudio
    postNotification(.iinaAIDChanged)
    if info.mixedAudioTrackIDs.count > 1 {
      if currentOSDFeedbackOrigin != .sidebar { sendOSD(.custom(String(format: NSLocalizedString("track.audio_mix_count", comment: "Active audio tracks"), info.mixedAudioTrackIDs.count))) }
    } else {
      let track = info.currentTrack(.audio) ?? .noneAudioTrack
      let position = info.orderedTrackList(.audio).firstIndex { $0.id == track.id }.map { $0 + 1 }
      sendOSD(.track(track, position: position))
    }
  }

  /// The mpv [audio-device-list](https://mpv.io/manual/stable/#command-interface-audio-device-list)
  /// property changed.
  /// - Important: The mpv [audio-device](https://mpv.io/manual/stable/#command-interface-audio-device)
  ///     property value is not guaranteed to reflect the audio device that is actually in use. When a selected device is removed the
  ///     value of this property continues to reflect the device that is no longer present even though `libmpv` has switched to
  ///     another audio device. This will cause the IINA `Audio Device` menu to malfunction. To handle the problematic behavior
  ///     of the `audio-device` property, whenever the device list changes this method checks if the device returned by
  ///     `audio-device` is present in the new list of audio devices. If the audio device cannot be found the `audio-device`
  ///     property is set to `auto` so that both IINA and mpv are in agreement on the selected audio device. For more information
  ///     see issue [#6034](https://github.com/iina/iina/issues/6034).
  func audioDeviceListChanged() {
    guard info.state.active else { return }
    let devices = getAudioDevices()
    let device = mpv.getString(MPVProperty.audioDevice)
    guard !devices.contains(where: {$0.name == device}) else { return }
    log("Selected audio device is no longer present, setting selected device to auto")
    setAudioDevice("auto")
  }

  func chapterChanged() {
    guard info.state.active else { return }
    info.chapter = Int(mpv.getInt(MPVProperty.chapter))
    syncUI(.time)
    postNotification(.iinaChapterListChanged)
    postNotification(.iinaMediaTitleChanged)
  }

  /// The mpv [current-ao](https://mpv.io/manual/stable/#command-interface-current-ao) property changed.
  ///
  /// When the audio output driver changes it may cause the currently selected audio device to be invalid because a mpv audio device
  /// is tied to a specific audio output driver. Attempt to find and configure the same audio device with the current audio output driver.
  func currentAoChanged() {
    guard let currentAo = mpv.getString(MPVProperty.currentAo),
          let audioDevice = mpv.getString(MPVProperty.audioDevice) else { return }
    let device = MPVAudioDevice(desc: "", name: audioDevice)
    let invalid = currentAo == "coreaudio" ? "avfoundation" : "coreaudio"
    guard device.driver == invalid else { return }
    let replacement = MPVAudioDevice(device, currentAo)
    let audioDevices = getAudioDevices()
    // Make certain the replacement device is in the list of audio devices.
    let found = audioDevices.contains { $0.name == replacement.name }
    guard found else {
      // Should not occur.
      log("Failed to find replacement audio device \(replacement.name) in:\n  \(audioDevices)",
          level: .error)
      return
    }
    log("""
        Audio output driver changed to \(currentAo), changing audio device
          from \(audioDevice)
          to \(replacement.name)
        """)
    mpv.setString(MPVProperty.audioDevice, replacement.name)
  }

  func fullscreenChanged() {
    guard mainWindow.loaded, info.state.active else { return }
    let fs = mpv.getFlag(MPVOption.Window.fullscreen)
    if fs != mainWindow.fsState.isFullscreen {
      mainWindow.toggleWindowFullScreen()
    }
  }

  func idleActiveChanged() {
    guard info.state != .shuttingDown, info.state != .shutDown else { return }
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
    // close the window if stopped
    if info.state.loaded ||  // stopped by mpv
        (info.state == .stopping && (currentWindow?.isVisible ?? false)) {  // user sent stop command
      DispatchQueue.main.async {
        self.currentController.close()
      }
    }
    if info.state != .loading {
      log("Playback has stopped")
      info.state = .idle
      postNotification(.iinaPlayerStopped)
      if shutdownRequestedAfterStop {
        shutdownRequestedAfterStop = false
        pendingUrl = nil
        shutdown()
        return
      }
      guard info.state == .idle else { pendingUrl = nil; return }
      if let pendingUrl {
        self.pendingUrl = nil
        log("Processing pending open")
        open(pendingUrl, shouldAutoLoad: pendingAutoLoad)
      }
    }
  }

  func mediaTitleChanged() {
    guard info.state.active else { return }
    postNotification(.iinaMediaTitleChanged)
  }

  func ontopChanged() {
    guard mainWindow.loaded, info.state.active else { return }
    let ontop = mpv.getFlag(MPVOption.Window.ontop)
    if ontop != mainWindow.isOntop {
      mainWindow.setWindowFloatingOnTop(ontop)
    }
  }

  func pauseChanged(_ paused: Bool) {
    guard mainWindow.loaded, info.state.loaded else { return }
    if (info.state == .paused) != paused {
      sendOSD(paused ? .pause : .resume)
      // The NowPlayingInfoManager is notified when playback is paused or resumed. The video
      // position must be updated before notifying the manager.
      syncUITime()
      info.state = paused ? .paused : .playing
      refreshSyncUITimer()
      // Follow energy efficiency best practices and ensure IINA is absolutely idle when the video
      // is paused to avoid wasting energy with needless processing. If paused shutdown the timer
      // that synchronizes the UI and the high priority display link thread.
      if paused {
        mainWindow.videoView.displayIdle()
      } else {
        mainWindow.videoView.displayActive()
      }
    }
    if Preference.bool(for: .alwaysFloatOnTop) {
      mainWindow.setWindowFloatingOnTop(!paused)
    }
    syncUI(.playButton)

    Task { @MainActor in
      if paused {
        mainWindow.liveText.requestAnalysis()
      } else {
        mainWindow.liveText.clearAnalysis()
      }
    }
  }

  func playbackRestarted() {
    finishPausedCropRefresh()
    mainWindow?.finishCropExitTransition(outputIsReady: true)
    mainWindow?.geometryVideoOutputDidChange(outputIsReady: true)
    mainWindow?.finishVideoAspectTransition()
    log("Playback restarted")

    // Important to synchronize the time as mpv may slightly alter the playback position during a
    // restart even while paused. See issue #5337.
    syncUI(.time)
    reloadSavedIINAfilters()

    // The new video's size is guaranteed to be available. Reset the flags used for window resizing.
    // We can't put this in MPV_EVENT_VIDEO_RECONFIG because it can be emitted with the old video's size
    // after switching to a new video.
    // We should keep these flags until a MPV_EVENT_VIDEO_RECONFIG with the new video's size.
    info.justOpenedFile = false
    info.justStartedFile = false

    NowPlayingInfoManager.shared.updateInfo()

    Task { @MainActor in
      mainWindow.liveText.clearAnalysis()
      mainWindow.liveText.requestAnalysis()
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
    postNotification(.iinaSubDelayChanged)
  }

  func secondarySubPosChanged(_ position: Double) {
    sendOSD(.secondSubPos(position))
    postNotification(.iinaSubPositionChanged)
  }

  func secondarySidChanged() {
    guard info.state.active else { return }
    info.secondSid = Int(mpv.getInt(MPVOption.Subtitles.secondarySid))
    postNotification(.iinaSIDChanged)
    sendOSD(.track(info.currentTrack(.secondSub) ?? .noneSubTrack))
    if isInMiniPlayer {
      miniPlayer.refreshArtworkVisibility()
    }
  }

  func secondSubVisibilityChanged(_ visible: Bool) {
    guard info.isSecondSubVisible != visible else { return }
    info.isSecondSubVisible = visible
    sendOSD(visible ? .secondSubVisible : .secondSubHidden)
    postNotification(.iinaSubVisibilityChanged)
    if isInMiniPlayer {
      miniPlayer.refreshArtworkVisibility()
    }
  }

  func sidChanged() {
    guard info.state.active else { return }
    info.sid = Int(mpv.getInt(MPVOption.TrackSelection.sid))
    postNotification(.iinaSIDChanged)
    sendOSD(.track(info.currentTrack(.sub) ?? .noneSubTrack))
    if isInMiniPlayer {
      miniPlayer.refreshArtworkVisibility()
    }
    Task { @MainActor in
      mainWindow.liveText.clearAnalysis()
      mainWindow.liveText.requestAnalysis()
    }
  }

  func subScaleChanged(_ scale: Double) {
    guard scale != 0 else { return }
    let displayValue = scale >= 1 ? scale : -1 / scale
    let truncated = round(displayValue * 100) / 100
    sendOSD(.subScale(truncated))
    postNotification(.iinaSubScaleChanged)
  }

  func speedChanged(_ speed: Double) {
    guard info.state.active else { return }
    info.playSpeed = speed
    sendOSD(.speed(speed))
    mainWindow.updateSpeedLabel(speed: speed)
    postNotification(.iinaSpeedChanged)
    NowPlayingInfoManager.shared.updateInfo()
  }

  func subDelayChanged(_ delay: Double) {
    info.subDelay = delay
    sendOSD(.subDelay(delay))
    postNotification(.iinaSubDelayChanged)
  }

  func subPosChanged(_ position: Double) {
    sendOSD(.subPos(position))
    postNotification(.iinaSubPositionChanged)
  }

  func subVisibilityChanged(_ visible: Bool) {
    guard info.isSubVisible != visible else { return }
    info.isSubVisible = visible
    sendOSD(visible ? .subVisible : .subHidden)
    postNotification(.iinaSubVisibilityChanged)
    if isInMiniPlayer {
      miniPlayer.refreshArtworkVisibility()
    }
  }

  func trackListChanged() {
    // No need to process track list changes if playback is being stopped. Must not process track
    // list changes if mpv is terminating as accessing mpv once shutdown has been initiated can
    // trigger a crash.
    guard info.state.active else { return }
    guard !deferCropRefreshUpdate(.tracks) else { return }
    log("Track list changed")
    getTrackInfo()
    getSelectedTracks()
    if let inputs = persistentAudioInputs,
       !inputs.isSubset(of: Set(info.audioTracks.map(\.id))) || !audioMixerInputsAreCompatible(inputs) {
      let previous = info.activeTrackIDs(.audio)
      var remaining = previous.intersection(info.audioTracks.map(\.id))
      if remaining.isEmpty, !previous.isEmpty, let first = info.audioTracks.first { remaining = [first.id] }
      setAudioTracks(remaining)
    }
    let audioStatus = info.isAudio

    // Now Playing is first updated when the file starts, before the track list is known, so the
    // media is treated as video and the artist and album are omitted. Update it again now.
    if self == PlayerCore.lastActive {
      NowPlayingInfoManager.shared.updateInfo(withTitle: true)
    }

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

    if isInMiniPlayer {
      miniPlayer.refreshArtworkVisibility()
      miniPlayer.handleVideoSizeChange()
    }

    postNotification(.iinaTracklistChanged)
  }

  func videoOutputSizeChanged() {
    guard mainWindow?.isCropTransitionInProgress == true else { return }
    onVideoReconfig(outputIsReady: true)
  }

  func onVideoReconfig(outputIsReady: Bool = false) {
    // If loading file, video reconfig can return 0 width and height
    guard info.state.loaded, !deferCropRefreshUpdate(.video) else { return }
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
    mainWindow?.finishCropExitTransition(outputIsReady: outputIsReady)
    mainWindow?.geometryVideoOutputDidChange()
  }

  func vfChanged() {
    guard info.state.active, !deferCropRefreshUpdate(.filters) else { return }
    postNotification(.iinaVFChanged)
  }

  func videoParamsChanged() {
    guard info.state.active, !deferCropRefreshUpdate(.videoParams) else { return }
    postNotification(.iinaVideoParamsChanged)
  }

  func vidChanged() {
    guard info.state.active else { return }
    info.vid = Int(mpv.getInt(MPVOption.TrackSelection.vid))
    reconcileTrackGraph()
    postNotification(.iinaVIDChanged)
    let selected = info.activeTrackIDs(.video)
    if selected.count <= 1 {
      let track = info.videoTracks.first { selected.contains($0.id) } ?? .noneVideoTrack
      let position = info.orderedTrackList(.video).firstIndex { $0.id == track.id }.map { $0 + 1 }
      sendOSD(.track(track, position: position))
    } else {
      if currentOSDFeedbackOrigin != .sidebar { sendOSD(.custom(String(format: NSLocalizedString("track.video_layer_count", comment: "Active video layers"), info.layeredVideoTrackIDs.count))) }
    }
    if isInMiniPlayer {
      miniPlayer.refreshArtworkVisibility()
      miniPlayer.handleVideoSizeChange()
    }

  }

  func windowScaleChanged() {
    // Loading/watch-later notifications may still carry the previous file's scale or dimensions.
    guard mainWindow.loaded, info.state.loaded, !info.justStartedFile, !info.justOpenedFile,
          !mainWindow.isCropTransitionInProgress else { return }
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

  /// Assess the need for the timer that synchronizes the UI and start or stop it as needed.
  ///
  /// Call this when `syncUITimer` may need to be started, stopped, or needs its interval changed. It will figure out the correct action.
  ///
  /// This method is required to adhere to the best practices in the [Energy Efficiency Guide for Mac Apps](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/UsingEfficientGraphics.html#//apple_ref/doc/uid/TP40013929-CH27-SW1)
  /// that call for an app to avoid needless energy use. [Minimizing Timer Usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html#//apple_ref/doc/uid/TP40013929-CH5-SW1) is one of the recommended best practices.
  /// - Important: Make sure that any state variables (e.g., `info.isPaused`, `isInMiniPlayer`,  etc.) are set *before*
  ///     calling this method, not after, so that it makes the correct decisions.
  func refreshSyncUITimer() {
    // Check if timer should start/restart

    let useTimer: Bool
    if !info.state.active {
      useTimer = false
    } else if info.state == .paused {
      // Ensure IINA is absolutely idle when the video is paused.
      useTimer = false
    } else if needsTouchBar && TouchBarSettings.shared.showAppControls || isInMiniPlayer {
      // The timer can't be stopped if the mini player is being used as it always displays the OSC
      // or if the timer is updating the information being displayed in the Touch Bar.
      useTimer = true
    } else if info.isNetworkResource {
      // May need to show, hide, or update buffering indicator at any time.
      useTimer = true
    } else {
      // Need if fadeable views or OSD are visible.
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

    if Logger.isEmitting(.verbose) {
      var summary = wasTimerRunning ? (useTimer ? "restarting" : "didStop") : (useTimer ? "starting" : "notNeeded")
      if summary != "notNeeded" {  // too many calls; try not to flood the log
        if useTimer {
          summary += ", timeInterval \(timeInterval)"
        }
        Logger.log("SyncUITimer \(summary). Player={state:\(info.state) network:\(info.isNetworkResource) mini:\(isInMiniPlayer) touchBar:\(needsTouchBar)}",
                   level: .verbose, subsystem: subsystem)
      }
    }

    // When fadeable views are hidden the time can get out of sync. This method will be called when
    // the view becomes visible to sync the time. If the timer was not running the view must be
    // updated now. Playback may be paused. If that is the case then the timer will not be started.
    if !wasTimerRunning {
      syncUITime()
    }

    guard useTimer else { return }

    // Timer will start
    syncUITimer = Timer.scheduledTimerInCommonMode(
      timeInterval: timeInterval,
      target: self,
      selector: #selector(self.syncUITime),
    )
  }

  func notifyWindowVideoSizeChanged() {
    currentController.handleVideoSizeChange()
    if currentController.pendingShow {
      currentController.pendingShow = false
      currentController.showWindow(self)
      AppDelegate.shared.openURLWindow.close()
    }
    if info.state == .loaded {
      // If the media was loaded manually then playback was paused to avoid audio starting to play
      // before video is ready to be displayed. Now that the video is ready playback can be resumed
      // unless the IINA "Pause" setting is enabled under "When media is opened".
      let paused = mpv.getFlag(MPVOption.PlaybackControl.pause)
      if paused, !Preference.bool(for: .pauseWhenOpen)  {
        log("Resuming playback now that file has been loaded")
        mainWindow.videoView.displayActive()
        mpv.setFlag(MPVOption.PlaybackControl.pause, false, level: .verbose)
      }
      info.state = Preference.bool(for: .pauseWhenOpen) ? .paused : .playing
      syncUI(.playButton)
      if Preference.bool(for: .fullScreenWhenOpen) && !mainWindow.fsState.isFullscreen && !isInMiniPlayer {
        mainWindow.toggleWindowFullScreen()
      }
    }
  }

  /// Synchronize the video position cached in the `info.videoPosition` property.
  ///
  /// This method updates the `PlaybackInfo.videoPosition` property.  If the video is being streamed `videoDuration` will
  /// also be updated.
  /// - Important: When the end of a video file is reached mpv does not update the value of the property
  ///     [time-pos](https://mpv.io/manual/stable/#command-interface-time-pos), leaving it reflecting the position
  ///     of the last frame of the video. This is especially noticeable if the onscreen controller time labels are configured to show
  ///     milliseconds. Due to this behavior of the `time-pos` property, this method checks to see of the end of the video has been
  ///     reached and if so, sets `videoPosition` to match `videoDuration`.
  private func syncPosition() {
    if info.isNetworkResource {
      info.videoDuration?.second = mpv.getDouble(MPVProperty.duration)
    }
    let eofReached = mpv.getFlag(MPVProperty.eofReached)
    if eofReached, let duration = info.videoDuration?.second {
      info.videoPosition?.second = duration
    } else {
      info.videoPosition?.second = mpv.getDouble(MPVProperty.timePos)
    }
    info.constrainVideoPosition()
  }

  /// Synchronize the cached video position if the timer that updates the cache is not running.
  ///
  /// When portions of the UI that need the video position are visible (OSC, OSD), `syncUITimer` keeps the
  /// `info.videoPosition` property synchronized with mpv. Code outside of the UI needs to call this method before accessing
  /// the position to ensure the cache is up to date when the timer is not running..
  func syncPositionIfNeeded() {
    if let syncUITimer, syncUITimer.isValid { return }
    guard info.state.active else { return }
    syncPosition()
  }

  // difficult to use option set
  enum SyncUIOption {
    case time
    case playButton
    case volume
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
      // A paused filter refresh seeks internally; its final position arrives with playback-restart.
      guard !isRefreshingPausedCrop, !mainWindow.isFullscreenTransitionInProgress else { return }
      let isNetworkStream = info.isNetworkResource
      syncPosition()
      info.videoRemaining?.second = Preference.bool(for: .scaleRemainingTime) ?
      mpv.getDouble(MPVProperty.playtimeRemainingFull) :
      mpv.getDouble(MPVProperty.timeRemainingFull)
      if isNetworkStream {
        // Update cache info
        info.pausedForCache = mpv.getFlag(MPVProperty.pausedForCache)
        let cacheState = mpv.getNode(MPVProperty.demuxerCacheState) as? [String: Any] ?? [:]
        info.cacheUsed = Int(cacheState["fw-bytes"] as? Int64 ?? 0)
        info.cacheSpeed = Int(cacheState["raw-input-rate"] as? Int64 ?? 0)
        info.cacheTime = mpv.getInt(MPVProperty.demuxerCacheTime)
        info.bufferingState = mpv.getInt(MPVProperty.cacheBufferingState)
      }
      DispatchQueue.main.async { [self] in
        currentController.updatePlayTime(withDuration: isNetworkStream, andProgressBar: true)
        if !self.isInMiniPlayer && mainWindow.fsState.isFullscreen && mainWindow.displayTimeAndBatteryInFullScreen && !mainWindow.additionalInfoView.isHidden {
          self.mainWindow.additionalInfoView.update()
        }
        if isNetworkStream {
          self.mainWindow.bufferIndicatorView.updateNetworkState()
        }
      }

    case .playButton:
      DispatchQueue.main.async { [self] in
        currentController.updatePlayButtonState(paused: info.state == .paused)
        touchBarSupport.updateTouchBarPlayBtn()
      }

    case .volume:
      DispatchQueue.main.async {
        self.currentController.updateVolume()
      }
    }
  }

  func sendOSD(_ osd: OSDMessage, autoHide: Bool = true, forcedTimeout: Float? = nil, accessoryView: NSView? = nil, context: Any? = nil, external: Bool = false) {
    guard external || currentOSDFeedbackOrigin != .sidebar || !osd.isSettingFeedback else { return }
    // querying `mainWindow.isWindowLoaded` will initialize mainWindow unexpectedly
    guard !isInMiniPlayer, mainWindow.loaded, info.state.active,
          Preference.bool(for: .enableOSD) || osd.alwaysEnabled, !osd.isDisabled else { return }
    if info.disableOSDForFileLoading && !external {
      guard case .fileStart = osd else {
        return
      }
    }
    DispatchQueue.main.async {
      guard self.info.state.active else { return }
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
            // OSC thumbnails may be used in Now Playing. Notify the manager thumbnails are now
            // available.
            DispatchQueue.main.async { NowPlayingInfoManager.shared.updateInfo() }
          } else {
            self.log("Cannot read thumbnail from cache", level: .error)
          }
        }
      } else {
        log("Request new thumbnails")
        ffmpegController.generateThumbnail(
          forFile: url.path,
          thumbWidth:Int32(Preference.integer(for: .thumbnailWidth)) * 2
        )
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
      let raw = mpv.getNode(MPVProperty.trackList)
      guard let list = raw as? [[String: Any]] else {
        // Internal error, should not occur.
        log("Cast of mpv node failed while getting track list: \(String(describing: raw))",
            level: .error)
        return
      }
      for dict in list {
        guard let track = MPVTrack(dict) else {
          // Internal error, should not occur.
          log("Unable to construct MPVTrack from mpv node map: \(dict)", level: .error)
          continue
        }
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
    info.aid = (info.mixedAudioTrackIDs.count == 1 ? info.mixedAudioTrackIDs.first : nil) ??
      mpv.getInt(MPVOption.TrackSelection.aid)
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
    guard info.state.active else { return }
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

    postNotification(.iinaChapterListChanged)
  }

  // MARK: - Notifications

  func postNotification(_ name: Notification.Name) {
    NotificationCenter.default.post(Notification(name: name, object: self))
  }

  /// Observer for changes to the macOS Touch Bar settings.
  /// - Parameters:
  ///   - keyPath: The key path, relative to `object`, to the value that has changed.
  ///   - object: The source object of the key path `keyPath`.
  ///   - change: A dictionary that describes the changes that have been made to the value of the property at the key path
  ///             `keyPath` relative to object. Entries are described in `Change Dictionary Keys`.
  ///   - context: The value that was provided when the observer was registered to receive key-value observation notifications.
  override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                             change: [NSKeyValueChangeKey: Any]?,
                             context: UnsafeMutableRawPointer?) {
    // The following guards are sanity checks and should never report an error.
    guard let keyPath else {
      log("Observed key path is missing", level: .error)
      return
    }
    guard let key = TouchBarSettings.Key(rawValue: keyPath) else {
      log("Observed key path is not a touch bar setting: \(keyPath)", level: .error)
      return
    }
    guard key == .PresentationModeFnModes || key == .PresentationModeGlobal ||
          key == .PresentationModePerApp else {
      log("Observed key path is unrecognized: \(keyPath)", level: .error)
      return
    }
    log("Touch Bar \(key) setting has changed")
    // The macOS settings that control what the Touch Bar displays has changed. May need to start or
    // stop the timer that refreshes the UI.
    refreshSyncUITimer()
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

  func interactiveVideoGeometry(uncropped: Bool) -> CropVideoGeometry {
    let property = uncropped ? MPVProperty.videoParams : MPVProperty.videoOutParams
    let width = mpv.getInt(property + "/w")
    let height = mpv.getInt(property + "/h")
    let displayWidth = mpv.getInt(property + "/dw")
    let displayHeight = mpv.getInt(property + "/dh")
    return CropVideoGeometry(
      sourceSize: NSSize(width: width, height: height),
      displaySize: NSSize(width: displayWidth, height: displayHeight),
      rotation: mpv.getInt(property + "/rotate"))
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
    let previousCrop = info.cropFilter
    let previousCropDescription = info.unsureCrop
    info.cropFilter = nil
    info.unsureCrop = "None"
    info.flipFilter = nil
    info.mirrorFilter = nil
    info.delogoFilter = nil
    let videoFilters = mpv.getFilters(MPVProperty.vf)
    for filter in videoFilters {
      guard let label = filter.label else { continue }
      switch label {
      case Constants.FilterName.crop:
        info.cropFilter = filter
        let unchanged = previousCrop?.isEqual(filter) == true
        info.unsureCrop = unchanged &&
          !["", "None"].contains(previousCropDescription) ? previousCropDescription : "Custom"
        // Watch-later retains the rectangle, but a fresh player has no preset name.
        // Match the centered source crop, not just its ratio: an offset/custom
        // rectangle must remain Custom. Source geometry may become available only
        // at playback-restart, after the preloaded hook first reads these filters.
        if info.unsureCrop == "Custom",
           !unchanged || ["", "None"].contains(previousCropDescription) || info.justStartedFile,
           filter.type == .crop, let params = filter.params,
           let width = params["w"].flatMap(Int.init), let height = params["h"].flatMap(Int.init),
           width > 0, height > 0 {
          let geometry = interactiveVideoGeometry(uncropped: true)
          if geometry.sourceSize.width > 0, geometry.sourceSize.height > 0,
             geometry.pixelAspectRatio.isFinite, geometry.pixelAspectRatio > 0 {
            let x = params["x"].flatMap(Int.init) ?? Int((geometry.sourceSize.width - CGFloat(width)) / 2)
            let y = params["y"].flatMap(Int.init) ?? Int((geometry.sourceSize.height - CGFloat(height)) / 2)
            for preset in AppData.cropsInPanel.dropFirst() + AppData.aspects {
              guard let aspect = Aspect(string: preset) else { continue }
              let pixelAspect = Aspect(size: NSSize(width: aspect.value / geometry.pixelAspectRatio, height: 1))
              let size = geometry.selectionSize.crop(withAspect: pixelAspect)
              let selection = size.centeredRect(in: NSRect(origin: .zero, size: geometry.selectionSize))
              let rect = geometry.filterRect(for: selection)
              if width == Int(rect.width), height == Int(rect.height), x == Int(rect.minX), y == Int(rect.minY) {
                info.unsureCrop = preset
                break
              }
            }
          }
        }
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
    info.audioEqFilter = nil
    let audioFilters = mpv.getFilters(MPVProperty.af)
    for filter in audioFilters {
      guard let label = filter.label else { continue }
      if label.hasPrefix(Constants.FilterName.audioEq) {
        info.audioEqFilter = filter
      }
    }
    let sameCrop = previousCrop?.isEqual(info.cropFilter) ?? (info.cropFilter == nil)
    if !sameCrop || previousCropDescription != info.unsureCrop {
      postNotification(.iinaTrackSettingsChanged)
    }
  }

  /**
   Get video duration, playback progress, and metadata, then save it to info.
   It may take some time to run this method, so it should be used in background.
   */
  func refreshCachedVideoInfo(forVideoPath path: String) {
    guard let dict = FFmpegController.probeVideoInfo(forFile: path) else { return }
    let progress: VideoTime? = {
      let url = URL(fileURLWithPath: path)
      let mpvMd5 = Utility.mpvWatchLaterMd5(url, ignorePathInWatchLaterConfig)
      return Utility.playbackProgressFromWatchLater(mpvMd5)
    }()
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
}

extension PlayerCore: FFmpegControllerDelegate {

  func didUpdate(_ thumbnails: [FFThumbnail]?, forFile filename: String, withProgress progress: Int) {
    guard let currentFilePath = info.currentURL?.path, currentFilePath == filename else { return }
    log("Got new thumbnails, progress \(progress)")
    if let thumbnails {
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
      // OSC thumbnails may be used in Now Playing. Notify the manager thumbnails are now available.
      DispatchQueue.main.async { NowPlayingInfoManager.shared.updateInfo() }
      if let cacheName = info.mpvMd5 {
        backgroundQueue.async {
          ThumbnailCache.write(self.info.thumbnails, forName: cacheName, forVideo: self.info.currentURL)
        }
      }
      events.emit(.thumbnailsReady)
    }
  }
}
