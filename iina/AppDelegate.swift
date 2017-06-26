//
//  AppDelegate.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa
import MASPreferences

fileprivate let intialWindowSize = NSSize(width: 640, height: 400)

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

  var isReady: Bool = false
  var handledDroppedText: Bool = false
  var handledURLEvent: Bool = false

  var pendingURL: String?

  private var lastOpenFileTimestamp: Double?

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

  func applicationWillFinishLaunching(_ notification: Notification) {
    // register for url event
    NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(self.handleURLEvent(event:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    if !isReady {
      UserDefaults.standard.register(defaults: Preference.defaultPreference)
      let pc = PlayerCore.first
      if UserDefaults.standard.bool(forKey: Preference.Key.showWelcomeWindow) {
        pc.mainWindow.showWindow(nil)
        pc.mainWindow.windowDidOpen()
      }
      menuController.bindMenuItems()
      isReady = true
    }

    // show alpha in color panels
    NSColorPanel.shared().showsAlpha = true

    // other
    if #available(OSX 10.12.2, *) {
      NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = false
      NSWindow.allowsAutomaticWindowTabbing = false
    }

    // pending open request
    if let url = pendingURL {
      parsePendingURL(url)
    }

    NSApplication.shared().servicesProvider = self
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }

  func applicationDidResignActive(_ notification: Notification) {

  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    guard PlayerCore.active.mainWindow.isWindowLoaded else { return false }
    return UserDefaults.standard.bool(forKey: Preference.Key.quitWhenNoOpenedWindow)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplicationTerminateReply {
    for pc in PlayerCore.playerCores {
     pc.terminateMPV()
    }
    return .terminateNow
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag, UserDefaults.standard.bool(forKey: Preference.Key.showWelcomeWindow), let mw = PlayerCore.first.mainWindow {
      let newFrame = mw.window!.frame.centeredResize(to: intialWindowSize)
      mw.window?.setFrame(newFrame, display: true)
      mw.window?.center()
      mw.window?.title = ""
      if #available(OSX 10.12.2, *) {
        mw.touchBarCurrentPosLabel?.stringValue = VideoTime.zero.stringRepresentation
      }
      mw.fadeableViews.forEach { $0.isHidden = true }
      mw.osdVisualEffectView.isHidden = true
      mw.initialWindowView.view.isHidden = false
      mw.showWindow(nil)
      mw.windowDidOpen()
    }
    return true
  }

  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    // When dragging multiple files to IINA icon, cocoa will simply call this method repeatedly.
    // IINA (mpv) can't handle opening multiple files correctly, so I have to guard it here.
    // It's a temperory solution, and the min time interval 0.3 might also be too arbitrary.
    let c = CFAbsoluteTimeGetCurrent()
    if let t = lastOpenFileTimestamp, c - t < 0.3 { return false }
    lastOpenFileTimestamp = c

    if !isReady {
      UserDefaults.standard.register(defaults: Preference.defaultPreference)
      let pc = PlayerCore.first
      if UserDefaults.standard.bool(forKey: Preference.Key.showWelcomeWindow) {
        pc.mainWindow.showWindow(nil)
        pc.mainWindow.windowDidOpen()
      }
      menuController.bindMenuItems()
      isReady = true
    }

    let url = URL(fileURLWithPath: filename)
    if UserDefaults.standard.bool(forKey: Preference.Key.recordRecentFiles) {
      NSDocumentController.shared().noteNewRecentDocumentURL(url)
    }
    PlayerCore.activeOrNew.openURL(url, isNetworkResource: false)
    return true
  }

  // MARK: - Accept dropped string and URL

  func droppedText(_ pboard: NSPasteboard, userData:String, error: NSErrorPointer) {
    if let url = pboard.string(forType: NSStringPboardType) {
      handledDroppedText = true
      PlayerCore.active.openURLString(url)
    }
  }

  func checkServiceStartup() {
    if !handledDroppedText && !handledURLEvent {
      openFile(self)
    }
  }
  
  // MARK: - Dock menu

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    return dockMenu
  }


  // MARK: - URL Scheme

  func handleURLEvent(event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
    handledURLEvent = true
    guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
    if isReady {
      parsePendingURL(url)
    } else {
      pendingURL = url
    }
  }

  func parsePendingURL(_ url: String) {
    guard let parsed = NSURLComponents(string: url) else { return }
    // links
    if let host = parsed.host, host == "weblink" {
      guard let urlValue = (parsed.queryItems?.filter { $0.name == "url" }.at(0)?.value) else { return }
      PlayerCore.active.openURLString(urlValue)
    }
  }

  // MARK: - Menu actions

  @IBAction func openFile(_ sender: AnyObject) {
    let panel = NSOpenPanel()
    panel.title = NSLocalizedString("alert.choose_media_file.title", comment: "Choose Media File")
    panel.canCreateDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.resolvesAliases = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == NSFileHandlingPanelOKButton {
      if let url = panel.url {
        if UserDefaults.standard.bool(forKey: Preference.Key.recordRecentFiles) {
          NSDocumentController.shared().noteNewRecentDocumentURL(url)
        }
        let playerCore: PlayerCore = (sender as? PlayerCore) ?? .activeOrNew
        playerCore.openURL(url, isNetworkResource: false)
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
    if response == NSAlertFirstButtonReturn {
      if let url = inputViewController.url {
        let playerCore: PlayerCore = (sender as? PlayerCore) ?? .activeOrNew
        playerCore.openURL(url, isNetworkResource: true)
      } else {
        Utility.showAlert("wrong_url_format")
      }
    }
  }

  @IBAction func menuNewWindow(_ sender: Any) {
    let pc = PlayerCore.newPlayerCore()
    pc.mainWindow.showWindow(nil)
    pc.mainWindow.windowDidOpen()
  }

  @IBAction func menuOpenScreenshotFolder(_ sender: NSMenuItem) {
    let screenshotPath = UserDefaults.standard.string(forKey: Preference.Key.screenshotFolder)!
    let absoluteScreenshotPath = NSString(string: screenshotPath).expandingTildeInPath
    let url = URL(fileURLWithPath: absoluteScreenshotPath, isDirectory: true)
      NSWorkspace.shared().open(url)
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
    NSWorkspace.shared().open(URL(string: AppData.wikiLink)!)
  }

  @IBAction func githubAction(_ sender: AnyObject) {
    NSWorkspace.shared().open(URL(string: AppData.githubLink)!)
  }

  @IBAction func websiteAction(_ sender: AnyObject) {
    NSWorkspace.shared().open(URL(string: AppData.websiteLink)!)
  }

  @IBAction func setSelfAsDefaultAction(_ sender: AnyObject) {
    Utility.setSelfAsDefaultForAllFileTypes()
  }

}
