//
//  AppDelegate.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MediaPlayer
import MASPreferences

/** Max time interval for repeated `application(_:openFile:)` calls. */
fileprivate let OpenFileRepeatTime = TimeInterval(0.2)
/** Tags for "Open File/URL" menu item when "ALways open file in new windows" is off. Vice versa. */
fileprivate let NormalMenuItemTag = 0
/** Tags for "Open File/URL in New Window" when "Always open URL" when "Open file in new windows" is off. Vice versa. */
fileprivate let AlternativeMenuItemTag = 1


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

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

  private var commandLineStatus = CommandLineStatus()

  // Windows

  lazy var aboutWindow: AboutWindowController = AboutWindowController()
  lazy var fontPicker: FontPickerWindowController = FontPickerWindowController()
  lazy var inspector: InspectorWindowController = InspectorWindowController()
  lazy var subSelectWindow: SubSelectWindowController = SubSelectWindowController()
  lazy var historyWindow: HistoryWindowController = HistoryWindowController()

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

  lazy var preferenceWindowController: NSWindowController = {
    return MASPreferencesWindowController(viewControllers: [
      PrefGeneralViewController(),
      PrefUIViewController(),
      PrefCodecViewController(),
      PrefSubViewController(),
      PrefNetworkViewController(),
      PrefControlViewController(),
      PrefKeyBindingViewController(),
      PrefAdvancedViewController(),
    ], title: NSLocalizedString("preference.title", comment: "Preference"))
  }()

  @IBOutlet weak var menuController: MenuController!

  @IBOutlet weak var dockMenu: NSMenu!

  // MARK: - App Delegate

  func applicationWillFinishLaunching(_ notification: Notification) {
    // register for url event
    NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(self.handleURLEvent(event:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

    // handle arguments
    let arguments = ProcessInfo.processInfo.arguments.dropFirst()
    guard arguments.count > 0 else { return }

    var iinaArgs: [String] = []
    var iinaArgFilenames: [String] = []
    var dropNextArg = false

    for arg in arguments {
      if dropNextArg {
        dropNextArg = false
        continue
      }
      if arg.first == "-" {
        if arg[arg.index(after: arg.startIndex)] == "-" {
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

    let (version, build) = Utility.iinaVersion()
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

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    if !isReady {
      UserDefaults.standard.register(defaults: Preference.defaultPreference)
      menuController.bindMenuItems()
      isReady = true
    }

    // show alpha in color panels
    NSColorPanel.shared.showsAlpha = true

    // other initializations at App level
    if #available(macOS 10.12.2, *) {
      NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = false
      NSWindow.allowsAutomaticWindowTabbing = false

      let remoteCommand = MPRemoteCommandCenter.shared()
      remoteCommand.playCommand.addTarget(handler: PlayerCore.handlePlayCommand(_:))
      remoteCommand.pauseCommand.addTarget(handler: PlayerCore.handlePauseCommand(_:))
      remoteCommand.togglePlayPauseCommand.addTarget(handler: PlayerCore.handleTogglePlayPauseCommand(_:))
      remoteCommand.stopCommand.addTarget(handler: PlayerCore.handleStopCommand(_:))
      remoteCommand.nextTrackCommand.addTarget(handler: PlayerCore.handleNextTrackCommand(_:))
      remoteCommand.previousTrackCommand.addTarget(handler: PlayerCore.handlePreviousTrackCommand(_:))

      NowPlayingInfoManager.updateState(.unknown)
    }

    // if have pending open request
    if let url = pendingURL {
      parsePendingURL(url)
    }

    let _ = PlayerCore.first

    if !commandLineStatus.isCommandLine {
      // check whether showing the welcome window after 0.1s
      Timer.scheduledTimer(timeInterval: TimeInterval(0.1), target: self, selector: #selector(self.checkForShowingInitialWindow), userInfo: nil, repeats: false)
    } else {
      let getNewPlayerCore = { () -> PlayerCore in
        let pc = PlayerCore.newPlayerCore
        self.commandLineStatus.assignMPVArguments(to: pc)
        return pc
      }
      if commandLineStatus.isStdin {
        getNewPlayerCore().openURLString("-")
      } else {
        let validFileURLs: [URL] = commandLineStatus.filenames.flatMap { filename in
          if Regex.url.matches(filename) {
            return URL(string: filename)
          } else {
            return FileManager.default.fileExists(atPath: filename) ? URL(fileURLWithPath: filename) : nil
          }
        }
        if commandLineStatus.openSeparateWindows {
          validFileURLs.forEach { url in
            let _ = getNewPlayerCore().openURLs([url])
          }
        } else {
          let _ = getNewPlayerCore().openURLs(validFileURLs)
        }
      }
    }

    NSApplication.shared.servicesProvider = self
  }

  /** Show welcome window if `application(_:openFile:)` wasn't called, i.e. launched normally. */
  @objc
  func checkForShowingInitialWindow() {
    if !openFileCalled {
      showWelcomeWindow()
    }
  }

  private func showWelcomeWindow() {
    let actionRawValue = Preference.integer(for: .actionAfterLaunch)
    let action: Preference.ActionAfterLaunch = Preference.ActionAfterLaunch(rawValue: actionRawValue) ?? .welcomeWindow
    switch action {
    case .welcomeWindow:
      PlayerCore.first.initialWindow.showWindow(nil)
    case .openPanel:
      openFile(self)
    default:
      break
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    guard PlayerCore.active.mainWindow.isWindowLoaded || PlayerCore.active.initialWindow.isWindowLoaded else { return false }
    return Preference.bool(for: .quitWhenNoOpenedWindow)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    for pc in PlayerCore.playerCores {
     pc.terminateMPV()
    }
    return .terminateNow
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    guard !flag else { return true }
    showWelcomeWindow()

    return true
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
      UserDefaults.standard.register(defaults: Preference.defaultPreference)
      menuController.bindMenuItems()
      isReady = true
    }
    // if launched from command line, should ignore openFile once
    if shouldIgnoreOpenFile {
      shouldIgnoreOpenFile = false
      return
    }
    // open pending files
    let urls = pendingFilesForOpenFile.map { URL(fileURLWithPath: $0) }

    pendingFilesForOpenFile.removeAll()
    if let openedFileCount = PlayerCore.activeOrNew.openURLs(urls), openedFileCount == 0 {
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


  // MARK: - URL Scheme

  @objc func handleURLEvent(event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
    openFileCalled = true
    guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
    if isReady {
      parsePendingURL(url)
    } else {
      pendingURL = url
    }
  }

  private func parsePendingURL(_ url: String) {
    guard let parsed = NSURLComponents(string: url) else { return }
    // links
    if let host = parsed.host, host == "weblink" {
      guard let urlValue = (parsed.queryItems?.first { $0.name == "url" }?.value) else { return }
      PlayerCore.active.openURLString(urlValue)
    }
  }

  // MARK: - Menu actions

  @IBAction func openFile(_ sender: AnyObject) {
    let panel = NSOpenPanel()
    panel.title = NSLocalizedString("alert.choose_media_file.title", comment: "Choose Media File")
    panel.canCreateDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    if panel.runModal() == .OK {
      if Preference.bool(for: .recordRecentFiles) {
        for url in panel.urls {
          NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
      }
      let isAlternative = (sender as? NSMenuItem)?.tag == AlternativeMenuItemTag
      let playerCore = PlayerCore.activeOrNewForMenuAction(isAlternative: isAlternative)
      if let openedFileCount = playerCore.openURLs(panel.urls), openedFileCount == 0 {
        Utility.showAlert("nothing_to_open")
      }
    }
  }

  @IBAction func openURL(_ sender: AnyObject) {
    let panel = NSAlert()
    panel.messageText = NSLocalizedString("alert.open_url.title", comment: "Open URL")
    panel.informativeText = NSLocalizedString("alert.open_url.message", comment: "Please enter the URL:")
    let inputViewController = OpenURLAccessoryViewController()
    panel.accessoryView = inputViewController.view
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.window.initialFirstResponder = inputViewController.urlField
    let response = panel.runModal()
    if response == .alertFirstButtonReturn {
      if let url = inputViewController.url {
        let playerCore = PlayerCore.activeOrNewForMenuAction(isAlternative: sender.tag == AlternativeMenuItemTag)
        playerCore.openURL(url, isNetworkResource: true)
      } else {
        Utility.showAlert("wrong_url_format")
      }
    }
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

  @IBAction func helpAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink)!)
  }

  @IBAction func githubAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.githubLink)!)
  }

  @IBAction func websiteAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.websiteLink)!)
  }

  @IBAction func setSelfAsDefaultAction(_ sender: AnyObject) {
    Utility.setSelfAsDefaultForAllFileTypes()
  }

}


struct CommandLineStatus {
  var isCommandLine = false
  var isStdin = false
  var openSeparateWindows = false
  var mpvArguments: [(String, String)] = []
  var iinaArguments: [(String, String)] = []
  var filenames: [String] = []

  mutating func parseArguments(_ args: [String]) {
    mpvArguments.removeAll()
    iinaArguments.removeAll()
    for arg in args {
      let splitted = arg.dropFirst(2).split(separator: "=", maxSplits: 2)
      let name = String(splitted[0])
      if (name.hasPrefix("mpv-")) {
        // mpv args
        if splitted.count <= 1 {
          mpvArguments.append((String(name.dropFirst(4)), "yes"))
        } else {
          mpvArguments.append((String(name.dropFirst(4)), String(splitted[1])))
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
      }
    }
  }

  func assignMPVArguments(to playerCore: PlayerCore) {
    for arg in mpvArguments {
      playerCore.mpv.setString(arg.0, arg.1)
    }
  }
}
