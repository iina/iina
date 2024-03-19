//
//  AppDelegate.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MediaPlayer
import Sparkle

let IINA_ENABLE_PLUGIN_SYSTEM = Preference.bool(for: .iinaEnablePluginSystem)

/** Max time interval for repeated `application(_:openFile:)` calls. */
fileprivate let OpenFileRepeatTime = TimeInterval(0.2)
/** Tags for "Open File/URL" menu item when "Always open file in new windows" is off. Vice versa. */
fileprivate let NormalMenuItemTag = 0
/** Tags for "Open File/URL in New Window" when "Always open URL" when "Open file in new windows" is off. Vice versa. */
fileprivate let AlternativeMenuItemTag = 1


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {

  /** Whether performed some basic initialization, like bind menu items. */
  var isReady = false
  /**
   Becomes true once `application(_:openFile:)` or `droppedText()` is called.
   Mainly used to distinguish normal launches from others triggered by drag-and-dropping files.
   */
  var openFileCalled = false
  var shouldIgnoreOpenFile = false
  /** Cached URL when launching from URL scheme. */
  var pendingURL: String?

  /** Cached file paths received in `application(_:openFile:)`. */
  private var pendingFilesForOpenFile: [String] = []
  /** The timer for `OpenFileRepeatTime` and `application(_:openFile:)`. */
  private var openFileTimer: Timer?

  private var allPlayersHaveShutdown = false

  private var commandLineStatus = CommandLineStatus()

  private var isTerminating = false

  /// Longest time to wait for asynchronous shutdown tasks to finish before giving up on waiting and proceeding with termination.
  ///
  /// Ten seconds was chosen to provide plenty of time for termination and yet not be long enough that users start thinking they will
  /// need to force quit IINA. As termination may involve logging out of an online subtitles provider it can take a while to complete if
  /// the provider is slow to respond to the logout request.
  private let terminationTimeout: TimeInterval = 10

  // Windows

  lazy var openURLWindow: OpenURLWindowController = OpenURLWindowController()
  lazy var aboutWindow: AboutWindowController = AboutWindowController()
  lazy var fontPicker: FontPickerWindowController = FontPickerWindowController()
  lazy var inspector: InspectorWindowController = InspectorWindowController()
  lazy var historyWindow: HistoryWindowController = HistoryWindowController()
  lazy var guideWindow: GuideWindowController = GuideWindowController()
  lazy var logWindow: LogWindowController = LogWindowController()

  lazy var vfWindow: FilterWindowController = {
    let w = FilterWindowController()
    w.filterType = MPVProperty.vf
    return w
  }()

  lazy var afWindow: FilterWindowController = {
    let w = FilterWindowController()
    w.filterType = MPVProperty.af
    return w
  }()

  lazy var preferenceWindowController: PreferenceWindowController = {
    var list: [NSViewController & PreferenceWindowEmbeddable] = [
      PrefGeneralViewController(),
      PrefUIViewController(),
      PrefCodecViewController(),
      PrefSubViewController(),
      PrefNetworkViewController(),
      PrefControlViewController(),
      PrefKeyBindingViewController(),
      PrefAdvancedViewController(),
      // PrefPluginViewController(),
      PrefUtilsViewController(),
    ]

    if IINA_ENABLE_PLUGIN_SYSTEM {
      list.insert(PrefPluginViewController(), at: 8)
    }
    return PreferenceWindowController(viewControllers: list)
  }()

  /// Whether the shutdown sequence timed out.
  private var timedOut = false

  @IBOutlet var menuController: MenuController!

  @IBOutlet weak var dockMenu: NSMenu!

  private func getReady() {
    menuController.bindMenuItems()
    PlayerCore.loadKeyBindings()
    isReady = true
  }

  // MARK: - Logs
  private let observedPrefKeys: [Preference.Key] = [.logLevel]

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }

    switch keyPath {
    case Preference.Key.logLevel.rawValue:
      if let newValue = change[.newKey] as? Int {
        Logger.Level.preferred = Logger.Level(rawValue: newValue.clamped(to: 0...3))!
      }

    default:
      return
    }
  }


  /// Log details about when and from what sources IINA was built.
  ///
  /// For developers that take a development build to other machines for testing it is useful to log information that can be used to
  /// distinguish between development builds.
  ///
  /// In support of this the build populated `Info.plist` with keys giving:
  /// - The build date
  /// - The git branch
  /// - The git commit
  private func logBuildDetails() {
    guard let branch = InfoDictionary.shared.buildBranch,
          let commit = InfoDictionary.shared.buildCommit,
          let date = InfoDictionary.shared.buildDate else { return }
    Logger.log("Built \(date) from branch \(branch), commit \(commit)")
  }

  /// Log details about the Mac IINA is running on.
  ///
  /// Certain IINA capabilities, such as hardware acceleration, are contingent upon aspects of the Mac IINA is running on. If available,
  /// this method will log:
  /// - macOS version
  /// - model identifier of the Mac
  /// - kind of processor
  private func logPlatformDetails() {
    Logger.log("Running under macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    guard let cpu = Sysctl.shared.machineCpuBrandString, let model = Sysctl.shared.hwModel else { return }
    Logger.log("On a \(model) with an \(cpu) processor")
  }

  // MARK: - SPUUpdaterDelegate
  @IBOutlet var updaterController: SPUStandardUpdaterController!

  func feedURLString(for updater: SPUUpdater) -> String? {
    return Preference.bool(for: .receiveBetaUpdate) ? AppData.appcastBetaLink : AppData.appcastLink
  }

  // MARK: - App Delegate

  func applicationWillFinishLaunching(_ notification: Notification) {
    // Must setup preferences before logging so log level is set correctly.
    registerUserDefaultValues()

    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    // Start the log file by logging the version of IINA producing the log file.
    let (version, build) = InfoDictionary.shared.version
    let type = InfoDictionary.shared.buildTypeIdentifier
    Logger.log("IINA \(version) Build \(build)" + (type == nil ? "" : " " + type!))

    // The copyright is used in the Finder "Get Info" window which is a narrow window so the
    // copyright consists of multiple lines.
    let copyright = InfoDictionary.shared.copyright
    copyright.enumerateLines { line, _ in
      Logger.log(line)
    }

    // Useful to know the versions of significant dependencies that are being used so log that
    // information as well when it can be obtained.

    // The version of mpv is not logged at this point because mpv does not provide a static
    // method that returns the version. To obtain version related information you must
    // construct a mpv object, which has side effects. So the mpv version is logged in
    // applicationDidFinishLaunching to preserve the existing order of initialization.

    Logger.log("FFmpeg \(String(cString: av_version_info()))")
    // FFmpeg libraries and their versions in alphabetical order.
    let libraries: [(name: String, version: UInt32)] = [("libavcodec", avcodec_version()), ("libavformat", avformat_version()), ("libavutil", avutil_version()), ("libswscale", swscale_version())]
    for library in libraries {
      // The version of FFmpeg libraries is encoded into an unsigned integer in a proprietary
      // format which needs to be decoded into a string for display.
      Logger.log("  \(library.name) \(AppDelegate.versionAsString(library.version))")
    }
    logBuildDetails()
    logPlatformDetails()

    Logger.log("App will launch")

    // Workaround macOS Sonoma clearing the recent documents list when the IINA code is not signed
    // with IINA's certificate as is the case for developer and nightly builds.
    restoreRecentDocuments()

    // register for url event
    NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(self.handleURLEvent(event:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

    // Check for legacy pref entries and migrate them to their modern equivalents
    LegacyMigration.migrateLegacyPreferences()

    // guide window
    if FirstRunManager.isFirstRun(for: .init("firstLaunchAfter\(version)")) {
      guideWindow.show(pages: [.highlights])
    }

    // Hide Window > "Enter Full Screen" menu item, because this is already present in the Video menu
    UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")

    // handle arguments
    let arguments = ProcessInfo.processInfo.arguments.dropFirst()
    guard arguments.count > 0 else { return }

    var iinaArgs: [String] = []
    var iinaArgFilenames: [String] = []
    var dropNextArg = false

    Logger.log("Command-line args: \(arguments)")
    for arg in arguments {
      if dropNextArg {
        dropNextArg = false
        continue
      }
      if arg.first == "-" {
        let indexAfterDash = arg.index(after: arg.startIndex)
        if indexAfterDash == arg.endIndex {
          // single '-'
          commandLineStatus.isStdin = true
        } else if arg[indexAfterDash] == "-" {
          // args starting with --
          iinaArgs.append(arg)
        } else {
          // args starting with -
          dropNextArg = true
        }
      } else {
        // assume args starting with nothing is a filename
        iinaArgFilenames.append(arg)
      }
    }

    commandLineStatus.parseArguments(iinaArgs)
    Logger.log("Filenames from args: \(iinaArgFilenames)")
    Logger.log("Derived mpv properties from args: \(commandLineStatus.mpvArguments)")

    print("IINA \(version) Build \(build)")

    guard !iinaArgFilenames.isEmpty || commandLineStatus.isStdin else {
      print("This binary is not intended for being used as a command line tool. Please use the bundled iina-cli.")
      print("Please ignore this message if you are running in a debug environment.")
      return
    }

    shouldIgnoreOpenFile = true
    commandLineStatus.isCommandLine = true
    commandLineStatus.filenames = iinaArgFilenames
  }

  deinit {
    ObjcUtils.silenced {
      for key in self.observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    Logger.log("App launched")

    if !isReady {
      getReady()
    }

    // see https://sparkle-project.org/documentation/api-reference/Classes/SPUUpdater.html#/c:objc(cs)SPUUpdater(im)clearFeedURLFromUserDefaults
    updaterController.updater.clearFeedURLFromUserDefaults()

    // show alpha in color panels
    NSColorPanel.shared.showsAlpha = true

    // other initializations at App level
    if #available(macOS 10.12.2, *) {
      NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = false
      NSWindow.allowsAutomaticWindowTabbing = false
    }

    JavascriptPlugin.loadGlobalInstances()
    let _ = PlayerCore.first
    Logger.log("Using \(PlayerCore.active.mpv.mpvVersion!)")

    if #available(macOS 10.13, *) {
      if RemoteCommandController.useSystemMediaControl {
        Logger.log("Setting up MediaPlayer integration")
        RemoteCommandController.setup()
        NowPlayingInfoManager.updateInfo(state: .unknown)
      }
    }

    // if have pending open request
    if let url = pendingURL {
      parsePendingURL(url)
    }

    if !commandLineStatus.isCommandLine {
      // check whether showing the welcome window after 0.1s
      Timer.scheduledTimer(timeInterval: TimeInterval(0.1), target: self, selector: #selector(self.checkForShowingInitialWindow), userInfo: nil, repeats: false)
    } else {
      var lastPlayerCore: PlayerCore? = nil
      let getNewPlayerCore = { [self] () -> PlayerCore in
        let pc = PlayerCore.newPlayerCore
        commandLineStatus.applyMPVArguments(to: pc)
        lastPlayerCore = pc
        return pc
      }
      if commandLineStatus.isStdin {
        getNewPlayerCore().openURLString("-")
      } else {
        let validFileURLs: [URL] = commandLineStatus.filenames.compactMap { filename in
          if Regex.url.matches(filename) {
            return URL(string: filename.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? filename)
          } else {
            return FileManager.default.fileExists(atPath: filename) ? URL(fileURLWithPath: filename) : nil
          }
        }
        if commandLineStatus.openSeparateWindows {
          validFileURLs.forEach { url in
            getNewPlayerCore().openURL(url)
          }
        } else {
          getNewPlayerCore().openURLs(validFileURLs)
        }
      }

      if let pc = lastPlayerCore {
        if commandLineStatus.enterMusicMode {
          if commandLineStatus.enterPIP {
            // PiP is not supported in music mode. Combining these options is not permitted and is
            // rejected by iina-cli. The IINA executable must have been invoked directly with
            // arguments.
            Logger.log("Cannot specify both --music-mode and --pip", level: .error)
            // Command line usage error.
            exit(EX_USAGE)
          }
          pc.switchToMiniPlayer()
        } else if #available(macOS 10.12, *), commandLineStatus.enterPIP {
          pc.mainWindow.enterPIP()
        }
      }
    }

    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

    NSApplication.shared.servicesProvider = self

    (NSApp.delegate as? AppDelegate)?.menuController?.updatePluginMenu()
  }

  /** Show welcome window if `application(_:openFile:)` wasn't called, i.e. launched normally. */
  @objc
  func checkForShowingInitialWindow() {
    if !openFileCalled {
      showWelcomeWindow()
    }
  }

  private func showWelcomeWindow(checkingForUpdatedData: Bool = false) {
    let actionRawValue = Preference.integer(for: .actionAfterLaunch)
    let action: Preference.ActionAfterLaunch = Preference.ActionAfterLaunch(rawValue: actionRawValue) ?? .welcomeWindow
    switch action {
    case .welcomeWindow:
      let window = PlayerCore.first.initialWindow!
      window.showWindow(nil)
      if checkingForUpdatedData {
        window.loadLastPlaybackInfo()
        window.reloadData()
      }
    case .openPanel:
      openFile(self)
    default:
      break
    }
  }

  func applicationShouldAutomaticallyLocalizeKeyEquivalents(_ application: NSApplication) -> Bool {
    // Do not re-map keyboard shortcuts based on keyboard position in different locales
    return false
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    guard PlayerCore.active.mainWindow.loaded || PlayerCore.active.initialWindow.loaded else { return false }
    guard !PlayerCore.active.mainWindow.isWindowHidden else { return false }
    return Preference.bool(for: .quitWhenNoOpenedWindow)
  }

  @objc
  func shutdownTimedout() {
    timedOut = true
    if !allPlayersHaveShutdown {
      Logger.log("Timed out waiting for players to stop and shutdown", level: .warning)
      // For debugging list players that have not terminated.
      for player in PlayerCore.playerCores {
        let label = player.label ?? "unlabeled"
        if !player.isStopped {
          Logger.log("Player \(label) failed to stop", level: .warning)
        } else if !player.isShutdown {
          Logger.log("Player \(label) failed to shutdown", level: .warning)
        }
      }
      // For debugging purposes we do not remove observers in case players stop or shutdown after
      // the timeout has fired as knowing that occurred maybe useful for debugging why the
      // termination sequence failed to complete on time.
      Logger.log("Not waiting for players to shutdown; proceeding with application termination",
                 level: .warning)
    }
    if OnlineSubtitle.loggedIn {
      // The request to log out of the online subtitles provider has not completed. This should not
      // occur as the logout request uses a timeout that is shorter than the termination timeout to
      // avoid this occurring. Therefore if this message is logged something has gone wrong with the
      // shutdown code.
      Logger.log("Timed out waiting for log out of online subtitles provider to complete",
                 level: .warning)
    }
    Logger.log("Proceeding with application termination due to time out", level: .warning)
    // Tell Cocoa to proceed with termination.
    NSApp.reply(toApplicationShouldTerminate: true)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Logger.log("App should terminate")
    isTerminating = true

    // Normally termination happens fast enough that the user does not have time to initiate
    // additional actions, however to be sure shutdown further input from the user.
    Logger.log("Disabling all menus")
    menuController.disableAllMenus()
    // Remove custom menu items added by IINA to the dock menu. AppKit does not allow the dock
    // supplied items to be changed by an application so there is no danger of removing them.
    // The menu items are being removed because setting the isEnabled property to false had no
    // effect under macOS 12.6.
    removeAllMenuItems(dockMenu)
    // If supported and enabled disable all remote media commands. This also removes IINA from
    // the Now Playing widget.
    if #available(macOS 10.13, *) {
      if RemoteCommandController.useSystemMediaControl {
        Logger.log("Disabling remote commands")
        RemoteCommandController.disableAllCommands()
      }
    }

    // The first priority was to shutdown any new input from the user. The second priority is to
    // send a logout request if logged into an online subtitles provider as that needs time to
    // complete.
    if OnlineSubtitle.loggedIn {
      // Force the logout request to timeout earlier than the overall termination timeout. This
      // request taking too long does not represent an error in the shutdown code, whereas the
      // intention of the overall termination timeout is to recover from some sort of hold up in the
      // shutdown sequence that should not occur.
      OnlineSubtitle.logout(timeout: terminationTimeout - 1)
    }

    // Close all windows. When a player window is closed it will send a stop command to mpv to stop
    // playback and unload the file.
    Logger.log("Closing all windows")
    for window in NSApp.windows {
      window.close()
    }

    // Check if there are any players that are not shutdown. If all players are already shutdown
    // then application termination can proceed immediately. This will happen if there is only one
    // player and shutdown was initiated by typing "q" in the player window. That sends a quit
    // command directly to mpv causing mpv and the player to shutdown before application
    // termination is initiated.
    allPlayersHaveShutdown = true
    for player in PlayerCore.playerCores {
      if !player.isShutdown {
        allPlayersHaveShutdown = false
        break
      }
    }
    if allPlayersHaveShutdown {
      Logger.log("All players have shutdown")
    } else {
      // Shutdown of player cores involves sending the stop and quit commands to mpv. Even though
      // these commands are sent to mpv using the synchronous API mpv executes them asynchronously.
      // This requires IINA to wait for mpv to finish executing these commands.
      Logger.log("Waiting for players to stop and shutdown")
    }

    // Usually will have to wait for logout request to complete if logged into an online subtitle
    // provider.
    var canTerminateNow = allPlayersHaveShutdown
    if OnlineSubtitle.loggedIn {
      canTerminateNow = false
      Logger.log("Waiting for log out of online subtitles provider to complete")
    }

    // If the user pressed Q and mpv initiated the termination then players will already be
    // shutdown and it may be possible to proceed with termination.
    if canTerminateNow {
      Logger.log("Proceeding with application termination")
      // Tell Cocoa that it is ok to immediately proceed with termination.
      return .terminateNow
    }

    // To ensure termination completes and the user is not required to force quit IINA, impose an
    // arbitrary timeout that forces termination to complete. The expectation is that this timeout
    // is never triggered. If a timeout warning is logged during termination then that needs to be
    // investigated.
    var timer: Timer
    if #available(macOS 10.12, *) {
      timer = Timer(timeInterval: terminationTimeout, repeats: false) { _ in
        // Once macOS 10.11 is no longer supported the contents of the method can be inlined in this
        // closure.
        self.shutdownTimedout()
      }
    } else {
      timer = Timer(timeInterval: terminationTimeout, target: self,
                    selector: #selector(self.shutdownTimedout), userInfo: nil, repeats: false)
    }
    RunLoop.main.add(timer, forMode: .common)

    // Establish an observer for a player core stopping.
    let center = NotificationCenter.default
    var observers: [NSObjectProtocol] = []
    var observer = center.addObserver(forName: .iinaPlayerStopped, object: nil, queue: .main) { note in
      guard !self.timedOut else {
        // The player has stopped after IINA already timed out, gave up waiting for players to
        // shutdown, and told Cocoa to proceed with termination. AppKit will continue to process
        // queued tasks during application termination even after AppKit has called
        // applicationWillTerminate. So this observer can be called after IINA has told Cocoa to
        // proceed with termination. When the termination sequence times out IINA does not remove
        // observers as it may be useful for debugging purposes to know that a player stopped after
        // the timeout as that indicates the stopping was proceeding as opposed to being permanently
        // blocked. Log that this has occurred and take no further action as it is too late to
        // proceed with the normal termination sequence.  If the log file has already been closed
        // then the message will only be printed to the console.
        Logger.log("Player stopped after application termination timed out", level: .warning)
        return
      }
      guard let player = note.object as? PlayerCore else { return }
      // Now that the player has stopped it is safe to instruct the player to terminate. IINA MUST
      // wait for the player to stop before instructing it to terminate because sending the quit
      // command to mpv while it is still asynchronously executing the stop command can result in a
      // watch later file that is missing information such as the playback position. See issue #3939
      // for details.
      player.shutdown()
    }
    observers.append(observer)

    /// Proceed with termination if all outstanding shutdown tasks have completed.
    ///
    /// This method is called when an observer receives a notification that a player has shutdown or an online subtitles provider logout
    /// request has completed. If there are no other termination tasks outstanding then this method will instruct AppKit to proceed with
    /// termination.
    func proceedWithTermination() {
      if !allPlayersHaveShutdown {
        // If any player has not shutdown then continue waiting.
        for player in PlayerCore.playerCores {
          guard player.isShutdown else { return }
        }
        allPlayersHaveShutdown = true
        // All players have shutdown.
        Logger.log("All players have shutdown")
      }
      guard !OnlineSubtitle.loggedIn else { return }
      // All players have shutdown. No longer logged into an online subtitles provider.
      Logger.log("Proceeding with application termination")
      // No longer need the timer that forces termination to proceed.
      timer.invalidate()
      // No longer need the observers for players stopping and shutting down, along with the
      // observer for logout requests completing.
      ObjcUtils.silenced {
        observers.forEach {
          NotificationCenter.default.removeObserver($0)
        }
      }
      // Tell AppKit to proceed with termination.
      NSApp.reply(toApplicationShouldTerminate: true)
    }

    // Establish an observer for a player core shutting down.
    observer = center.addObserver(forName: .iinaPlayerShutdown, object: nil, queue: .main) { _ in
      guard !self.timedOut else {
        // The player has shutdown after IINA already timed out, gave up waiting for players to
        // shutdown, and told Cocoa to proceed with termination. AppKit will continue to process
        // queued tasks during application termination even after AppKit has called
        // applicationWillTerminate. So this observer can be called after IINA has told Cocoa to
        // proceed with termination. When the termination sequence times out IINA does not remove
        // observers as it may be useful for debugging purposes to know that a player shutdown after
        // the timeout as that indicates shutdown was proceeding as opposed to being permanently
        // blocked. Log that this has occurred and take no further action as it is too late to
        // proceed with the normal termination sequence. If the log file has already been closed
        // then the message will only be printed to the console.
        Logger.log("Player shutdown after application termination timed out", level: .warning)
        return
      }
      proceedWithTermination()
    }
    observers.append(observer)

    // Establish an observer for logging out of the online subtitle provider.
    observer = center.addObserver(forName: .iinaLogoutCompleted, object: nil, queue: .main) { _ in
      guard !self.timedOut else {
        // The request to log out of the online subtitles provider has completed after IINA already
        // timed out, gave up waiting for players to shutdown, and told Cocoa to proceed with
        // termination. This should not occur as the logout request uses a timeout that is shorter
        // than the termination timeout to avoid this occurring. Therefore if this message is logged
        // something has gone wrong with the shutdown code.
        Logger.log(
          "Log out of online subtitles provider completed after application termination timed out",
          level: .warning)
        return
      }
      proceedWithTermination()
    }
    observers.append(observer)

    // Instruct any players that are already stopped to start shutting down.
    for player in PlayerCore.playerCores {
      if player.isStopped && !player.isShutdown {
        player.shutdown()
      }
    }

    // Tell AppKit that it is ok to proceed with termination, but wait for our reply.
    return .terminateLater
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // Once termination starts subsystems such as mpv are being shutdown. Accessing mpv
    // once it has been instructed to shutdown can trigger a crash. MUST NOT permit
    // reopening once termination has started.
    guard !isTerminating else { return false }
    guard !flag else { return true }
    Logger.log("Handle reopen")
    showWelcomeWindow(checkingForUpdatedData: true)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    Logger.log("App will terminate")
    Logger.closeLogFile()
  }

  /**
   When dragging multiple files to App icon, cocoa will simply call this method repeatedly.
   Therefore we must cache all possible calls and handle them together.
   */
  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    openFileCalled = true
    openFileTimer?.invalidate()
    pendingFilesForOpenFile.append(filename)
    openFileTimer = Timer.scheduledTimer(timeInterval: OpenFileRepeatTime, target: self, selector: #selector(handleOpenFile), userInfo: nil, repeats: false)
    return true
  }

  /** Handle pending file paths if `application(_:openFile:)` not being called again in `OpenFileRepeatTime`. */
  @objc
  func handleOpenFile() {
    if !isReady {
      getReady()
    }
    // if launched from command line, should ignore openFile once
    if shouldIgnoreOpenFile {
      shouldIgnoreOpenFile = false
      return
    }
    let urls = pendingFilesForOpenFile.map { URL(fileURLWithPath: $0) }
    
    // if installing a plugin package
    if let pluginPackageURL = urls.first(where: { $0.pathExtension == "iinaplgz" }) {
      showPreferences(self)
      preferenceWindowController.performAction(.installPlugin(url: pluginPackageURL))
      return
    }

    // open pending files
    pendingFilesForOpenFile.removeAll()
    if PlayerCore.activeOrNew.openURLs(urls) == 0 {
      Utility.showAlert("nothing_to_open")
    }
  }

  // MARK: - Accept dropped string and URL

  @objc
  func droppedText(_ pboard: NSPasteboard, userData:String, error: NSErrorPointer) {
    if let url = pboard.string(forType: .string) {
      openFileCalled = true
      PlayerCore.active.openURLString(url)
    }
  }

  // MARK: - Dock menu

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    return dockMenu
  }

  /// Remove all menu items in the given menu and any submenus.
  ///
  /// This method recursively descends through the entire tree of menu items removing all items.
  /// - Parameter menu: Menu to remove items from
  private func removeAllMenuItems(_ menu: NSMenu) {
    for item in menu.items {
      if item.hasSubmenu {
        removeAllMenuItems(item.submenu!)
      }
      menu.removeItem(item)
    }
  }

  // MARK: - URL Scheme

  @objc func handleURLEvent(event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
    openFileCalled = true
    guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
    Logger.log("URL event: \(url)")
    if isReady {
      parsePendingURL(url)
    } else {
      pendingURL = url
    }
  }


  /**
   Parses the pending iina:// url.
   - Parameter url: the pending URL.
   - Note:
   The iina:// URL scheme currently supports the following actions:

   __/open__
   - `url`: a url or string to open.
   - `new_window`: 0 or 1 (default) to indicate whether open the media in a new window.
   - `enqueue`: 0 (default) or 1 to indicate whether to add the media to the current playlist.
   - `full_screen`: 0 (default) or 1 to indicate whether open the media and enter fullscreen.
   - `pip`: 0 (default) or 1 to indicate whether open the media and enter pip.
   - `mpv_*`: additional mpv options to be passed. e.g. `mpv_volume=20`.
     Options starting with `no-` are not supported.
   */
  private func parsePendingURL(_ url: String) {
    Logger.log("Parsing URL \(url)")
    guard let parsed = URLComponents(string: url) else {
      Logger.log("Cannot parse URL using URLComponents", level: .warning)
      return
    }
    
    if parsed.scheme != "iina" {
      // try to open the URL directly
      PlayerCore.activeOrNewForMenuAction(isAlternative: false).openURLString(url)
      return
    }
    
    // handle url scheme
    guard let host = parsed.host else { return }

    if host == "open" || host == "weblink" {
      // open a file or link
      guard let queries = parsed.queryItems else { return }
      let queryDict = [String: String](uniqueKeysWithValues: queries.map { ($0.name, $0.value ?? "") })

      // url
      guard let urlValue = queryDict["url"], !urlValue.isEmpty else {
        Logger.log("Cannot find parameter \"url\", stopped")
        return
      }

      // new_window
      let player: PlayerCore
      if let newWindowValue = queryDict["new_window"], newWindowValue == "1" {
        player = PlayerCore.newPlayerCore
      } else {
        player = PlayerCore.activeOrNewForMenuAction(isAlternative: false)
      }

      // enqueue
      if let enqueueValue = queryDict["enqueue"], enqueueValue == "1", !PlayerCore.lastActive.info.playlist.isEmpty {
        PlayerCore.lastActive.addToPlaylist(urlValue)
        PlayerCore.lastActive.postNotification(.iinaPlaylistChanged)
        PlayerCore.lastActive.sendOSD(.addToPlaylist(1))
      } else {
        player.openURLString(urlValue)
      }

      // presentation options
      if let fsValue = queryDict["full_screen"], fsValue == "1" {
        // full_screeen
        player.mpv.setFlag(MPVOption.Window.fullscreen, true)
      } else if let pipValue = queryDict["pip"], pipValue == "1" {
        // pip
        if #available(macOS 10.12, *) {
          player.mainWindow.enterPIP()
        }
      }

      // mpv options
      for query in queries {
        if query.name.hasPrefix("mpv_") {
          let mpvOptionName = String(query.name.dropFirst(4))
          guard let mpvOptionValue = query.value else { continue }
          Logger.log("Setting \(mpvOptionName) to \(mpvOptionValue)")
          player.mpv.setString(mpvOptionName, mpvOptionValue)
        }
      }

      Logger.log("Finished URL scheme handling")
    }
  }

  // MARK: - Menu actions

  @IBAction func openFile(_ sender: AnyObject) {
    Logger.log("Menu - Open file")
    let panel = NSOpenPanel()
    panel.title = NSLocalizedString("alert.choose_media_file.title", comment: "Choose Media File")
    panel.canCreateDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    if panel.runModal() == .OK {
      if Preference.bool(for: .recordRecentFiles) {
        for url in panel.urls {
          noteNewRecentDocumentURL(url)
        }
      }
      let isAlternative = (sender as? NSMenuItem)?.tag == AlternativeMenuItemTag
      let playerCore = PlayerCore.activeOrNewForMenuAction(isAlternative: isAlternative)
      if playerCore.openURLs(panel.urls) == 0 {
        Utility.showAlert("nothing_to_open")
      }
    }
  }

  @IBAction func openURL(_ sender: AnyObject) {
    Logger.log("Menu - Open URL")
    openURLWindow.isAlternativeAction = sender.tag == AlternativeMenuItemTag
    openURLWindow.showWindow(nil)
    openURLWindow.resetFields()
  }

  @IBAction func menuNewWindow(_ sender: Any) {
    PlayerCore.newPlayerCore.initialWindow.showWindow(nil)
  }

  @IBAction func menuOpenScreenshotFolder(_ sender: NSMenuItem) {
    let screenshotPath = Preference.string(for: .screenshotFolder)!
    let absoluteScreenshotPath = NSString(string: screenshotPath).expandingTildeInPath
    let url = URL(fileURLWithPath: absoluteScreenshotPath, isDirectory: true)
      NSWorkspace.shared.open(url)
  }

  @IBAction func menuSelectAudioDevice(_ sender: NSMenuItem) {
    if let name = sender.representedObject as? String {
      PlayerCore.active.setAudioDevice(name)
    }
  }

  @IBAction func showPreferences(_ sender: AnyObject) {
    preferenceWindowController.showWindow(self)
  }

  @IBAction func showVideoFilterWindow(_ sender: AnyObject) {
    vfWindow.showWindow(self)
  }

  @IBAction func showAudioFilterWindow(_ sender: AnyObject) {
    afWindow.showWindow(self)
  }

  @IBAction func showAboutWindow(_ sender: AnyObject) {
    aboutWindow.showWindow(self)
  }

  @IBAction func showHistoryWindow(_ sender: AnyObject) {
    historyWindow.showWindow(self)
  }

  @IBAction func showLogWindow(_ sender: AnyObject) {
    logWindow.showWindow(self)
  }

  @IBAction func showHighlights(_ sender: AnyObject) {
    guideWindow.show(pages: [.highlights])
  }

  @IBAction func helpAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink)!)
  }

  @IBAction func githubAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.githubLink)!)
  }

  @IBAction func websiteAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.websiteLink)!)
  }

  private func registerUserDefaultValues() {
    UserDefaults.standard.register(defaults: [String: Any](uniqueKeysWithValues: Preference.defaultPreference.map { ($0.0.rawValue, $0.1) }))
  }

  // MARK: - FFmpeg version parsing

  /// Extracts the major version number from the given FFmpeg encoded version number.
  ///
  /// This is a Swift implementation of the FFmpeg macro `AV_VERSION_MAJOR`.
  /// - Parameter version: Encoded version number in FFmpeg proprietary format.
  /// - Returns: The major version number
  private static func avVersionMajor(_ version: UInt32) -> UInt32 {
    version >> 16
  }

  /// Extracts the minor version number from the given FFmpeg encoded version number.
  ///
  /// This is a Swift implementation of the FFmpeg macro `AV_VERSION_MINOR`.
  /// - Parameter version: Encoded version number in FFmpeg proprietary format.
  /// - Returns: The minor version number
  private static func avVersionMinor(_ version: UInt32) -> UInt32 {
    (version & 0x00FF00) >> 8
  }

  /// Extracts the micro version number from the given FFmpeg encoded version number.
  ///
  /// This is a Swift implementation of the FFmpeg macro `AV_VERSION_MICRO`.
  /// - Parameter version: Encoded version number in FFmpeg proprietary format.
  /// - Returns: The micro version number
  private static func avVersionMicro(_ version: UInt32) -> UInt32 {
    version & 0xFF
  }

  /// Forms a string representation from the given FFmpeg encoded version number.
  ///
  /// FFmpeg returns the version number of its libraries encoded into an unsigned integer. The FFmpeg source
  /// `libavutil/version.h` describes FFmpeg's versioning scheme and provides C macros for operating on encoded
  /// version numbers. Since the macros can't be used in Swift code we've had to code equivalent functions in Swift.
  /// - Parameter version: Encoded version number in FFmpeg proprietary format.
  /// - Returns: A string containing the version number.
  private static func versionAsString(_ version: UInt32) -> String {
    let major = AppDelegate.avVersionMajor(version)
    let minor = AppDelegate.avVersionMinor(version)
    let micro = AppDelegate.avVersionMicro(version)
    return "\(major).\(minor).\(micro)"
  }

  // MARK: - Recent Documents

  /// Empties the recent documents list for the application.
  ///
  /// This is part of a workaround for macOS Sonoma clearing the list of recent documents. See the method
  /// `restoreRecentDocuments` and the issue [#4688](https://github.com/iina/iina/issues/4688) for more
  /// information..
  /// - Parameter sender: The object that initiated the clearing of the recent documents.
  @IBAction
  func clearRecentDocuments(_ sender: Any?) {
    NSDocumentController.shared.clearRecentDocuments(sender)
    saveRecentDocuments()
  }

  /// Adds or replaces an Open Recent menu item corresponding to the data located by the URL.
  ///
  /// This is part of a workaround for macOS Sonoma clearing the list of recent documents. See the method
  /// `restoreRecentDocuments` and the issue [#4688](https://github.com/iina/iina/issues/4688) for more
  /// information..
  /// - Parameter url: The URL to evaluate.
  func noteNewRecentDocumentURL(_ url: URL) {
    NSDocumentController.shared.noteNewRecentDocumentURL(url)
    saveRecentDocuments()
  }

  /// Restore the list of recently opened files.
  ///
  /// For macOS Sonoma `sharedfilelistd` was changed to tie the list of recent documents to the app based on its certificate.
  /// if `sharedfilelistd` determines the list is being accessed by a different app then it clears the list. See issue
  /// [#4688](https://github.com/iina/iina/issues/4688) for details.
  ///
  /// This new behavior does not cause a problem when the code is signed with IINA's certificate. However developer and nightly
  /// builds use an ad hoc certificate. This causes the list of recently opened files to be cleared each time a different unsigned IINA build
  /// is run. As a workaround a copy of the list of recent documents is saved in IINA's preference file to preserve the list and allow it to
  /// be restored when `sharedfilelistd` clears its list.
  ///
  /// If the following is true:
  /// - Running under macOS Sonoma and above
  /// - Recording of recent files is enabled
  /// - The list in  [NSDocumentController.shared.recentDocumentURLs](https://developer.apple.com/documentation/appkit/nsdocumentcontroller/1514976-recentdocumenturls) is empty
  /// - The list in the IINA setting `recentDocuments` is not empty
  ///
  /// Then this method assumes that the macOS daemon `sharedfilelistd` cleared the list and it populates the list of recent
  /// document URLs with the list stored in IINA's settings.
  private func restoreRecentDocuments() {
    guard #available(macOS 14, *), Preference.bool(for: .recordRecentFiles),
          NSDocumentController.shared.recentDocumentURLs.isEmpty,
          let recentDocuments = Preference.array(for: .recentDocuments),
          !recentDocuments.isEmpty else { return }
    var foundStale = false
    for document in recentDocuments {
      var isStale = false
      guard let asData = document as? Data,
            let bookmark = try? URL(resolvingBookmarkData: asData, bookmarkDataIsStale: &isStale) else {
        guard let asString = document as? String, let url = URL(string: asString) else { continue }
        // Saving as a bookmark must have failed and instead the URL was saved as a string.
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        continue
      }
      foundStale = foundStale || isStale
      NSDocumentController.shared.noteNewRecentDocumentURL(bookmark)
    }
    Logger.log("Restored list of recent documents")
    guard foundStale else { return }
    Logger.log("Found stale bookmarks in saved recent documents")
    // Save the recent documents in order to refresh stale bookmarks.
    saveRecentDocuments()
  }

  /// Save the list of recently opened files.
  ///
  /// Save the list of recent documents in [NSDocumentController.shared.recentDocumentURLs](https://developer.apple.com/documentation/appkit/nsdocumentcontroller/1514976-recentdocumenturls)
  /// to `recentDocuments` in the IINA settings property file.
  ///
  /// This is part of a workaround for macOS Sonoma clearing the list of recent documents. See the method
  /// `restoreRecentDocuments` and the issue [#4688](https://github.com/iina/iina/issues/4688) for more
  /// information..
  func saveRecentDocuments() {
    guard #available(macOS 14, *) else { return }
    var recentDocuments: [Any] = []
    for document in NSDocumentController.shared.recentDocumentURLs {
      guard let bookmark = try? document.bookmarkData() else {
        // Fall back to storing a string when unable to create a bookmark.
        recentDocuments.append(document.absoluteString)
        continue
      }
      recentDocuments.append(bookmark)
    }
    Preference.set(recentDocuments, for: .recentDocuments)
    if recentDocuments.isEmpty {
      Logger.log("Cleared list of recent documents")
    } else {
      Logger.log("Saved list of recent documents")
    }
  }
}


struct CommandLineStatus {
  var isCommandLine = false
  var isStdin = false
  var openSeparateWindows = false
  var enterMusicMode = false
  var enterPIP = false
  var mpvArguments: [(String, String)] = []
  var iinaArguments: [(String, String)] = []
  var filenames: [String] = []

  mutating func parseArguments(_ args: [String]) {
    mpvArguments.removeAll()
    iinaArguments.removeAll()
    for arg in args {
      let splitted = arg.dropFirst(2).split(separator: "=", maxSplits: 1)
      let name = String(splitted[0])
      if (name.hasPrefix("mpv-")) {
        // mpv args
        let strippedName = String(name.dropFirst(4))
        if strippedName == "-" {
          isStdin = true
        } else {
          let argPair: (String, String)
          if splitted.count <= 1 {
            argPair = (strippedName, "yes")
          } else {
            argPair = (strippedName, String(splitted[1]))
          }
          mpvArguments.append(argPair)
        }
      } else {
        // other args
        if splitted.count <= 1 {
          iinaArguments.append((name, "yes"))
        } else {
          iinaArguments.append((name, String(splitted[1])))
        }
        if name == "stdin" {
          isStdin = true
        }
        if name == "separate-windows" {
          openSeparateWindows = true
        }
        if name == "music-mode" {
          enterMusicMode = true
        }
        if name == "pip" {
          enterPIP = true
        }
      }
    }
  }

  func applyMPVArguments(to playerCore: PlayerCore) {
    Logger.log("Setting mpv properties from arguments: \(mpvArguments)")
    for argPair in mpvArguments {
      if argPair.0 == "shuffle" && argPair.1 == "yes" {
        // Special handling for this one
        Logger.log("Found \"shuffle\" request in command-line args. Adding mpv hook to shuffle playlist")
        playerCore.addShufflePlaylistHook()
        continue
      }
      playerCore.mpv.setString(argPair.0, argPair.1)
    }
  }
}

@available(macOS 10.13, *)
class RemoteCommandController {
  static let remoteCommand = MPRemoteCommandCenter.shared()

  static var useSystemMediaControl: Bool = Preference.bool(for: .useMediaKeys)

  static func setup() {
    remoteCommand.playCommand.addTarget { _ in
      PlayerCore.lastActive.resume()
      return .success
    }
    remoteCommand.pauseCommand.addTarget { _ in
      PlayerCore.lastActive.pause()
      return .success
    }
    remoteCommand.togglePlayPauseCommand.addTarget { _ in
      PlayerCore.lastActive.togglePause()
      return .success
    }
    remoteCommand.stopCommand.addTarget { _ in
      PlayerCore.lastActive.stop()
      return .success
    }
    remoteCommand.nextTrackCommand.addTarget { _ in
      PlayerCore.lastActive.navigateInPlaylist(nextMedia: true)
      return .success
    }
    remoteCommand.previousTrackCommand.addTarget { _ in
      PlayerCore.lastActive.navigateInPlaylist(nextMedia: false)
      return .success
    }
    remoteCommand.changeRepeatModeCommand.addTarget { _ in
      PlayerCore.lastActive.nextLoopMode()
      return .success
    }
    remoteCommand.changeShuffleModeCommand.isEnabled = false
    // remoteCommand.changeShuffleModeCommand.addTarget {})
    remoteCommand.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1, 1.5, 2]
    remoteCommand.changePlaybackRateCommand.addTarget { event in
      PlayerCore.lastActive.setSpeed(Double((event as! MPChangePlaybackRateCommandEvent).playbackRate))
      return .success
    }
    remoteCommand.skipForwardCommand.preferredIntervals = [15]
    remoteCommand.skipForwardCommand.addTarget { event in
      PlayerCore.lastActive.seek(relativeSecond: (event as! MPSkipIntervalCommandEvent).interval, option: .exact)
      return .success
    }
    remoteCommand.skipBackwardCommand.preferredIntervals = [15]
    remoteCommand.skipBackwardCommand.addTarget { event in
      PlayerCore.lastActive.seek(relativeSecond: -(event as! MPSkipIntervalCommandEvent).interval, option: .exact)
      return .success
    }
    remoteCommand.changePlaybackPositionCommand.addTarget { event in
      PlayerCore.lastActive.seek(absoluteSecond: (event as! MPChangePlaybackPositionCommandEvent).positionTime)
      return .success
    }
  }

  static func disableAllCommands() {
    remoteCommand.playCommand.removeTarget(nil)
    remoteCommand.pauseCommand.removeTarget(nil)
    remoteCommand.togglePlayPauseCommand.removeTarget(nil)
    remoteCommand.stopCommand.removeTarget(nil)
    remoteCommand.nextTrackCommand.removeTarget(nil)
    remoteCommand.previousTrackCommand.removeTarget(nil)
    remoteCommand.changeRepeatModeCommand.removeTarget(nil)
    remoteCommand.changeShuffleModeCommand.removeTarget(nil)
    remoteCommand.changePlaybackRateCommand.removeTarget(nil)
    remoteCommand.skipForwardCommand.removeTarget(nil)
    remoteCommand.skipBackwardCommand.removeTarget(nil)
    remoteCommand.changePlaybackPositionCommand.removeTarget(nil)
  }
}
