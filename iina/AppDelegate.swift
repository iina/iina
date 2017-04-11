//
//  AppDelegate.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa
import MASPreferences

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

  var isReady: Bool = false

  var pendingURL: String?

  lazy var playerCore: PlayerCore = PlayerCore.shared

  lazy var aboutWindow: AboutWindowController = AboutWindowController()

  lazy var fontPicker: FontPickerWindowController = FontPickerWindowController()

  lazy var inspector: InspectorWindowController = InspectorWindowController()

  lazy var subSelectWindow: SubSelectWindowController = SubSelectWindowController()

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
      playerCore.startMPV()
      menuController.bindMenuItems()
      isReady = true

      if UserDefaults.standard.bool(forKey: Preference.Key.openStartPanel) {
        // invoke after 0.5s
        Timer.scheduledTimer(timeInterval: TimeInterval(0.5), target: self, selector: #selector(self.openFile(_:)), userInfo: nil, repeats: false)
      }
    }

    // show alpha in color panels
    NSColorPanel.shared().showsAlpha = true

    // other
    if #available(OSX 10.12.2, *) {
      NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = false
      NSWindow.allowsAutomaticWindowTabbing = false
    }

    // check update
    UpdateChecker.checkUpdate(alertIfOfflineOrNoUpdate: false)

    // pending open request
    if let url = pendingURL {
      parsePendingURL(url)
    }
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }

  func applicationDidResignActive(_ notification: Notification) {

  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    guard let mw = playerCore.mainWindow, mw.isWindowLoaded else { return false }
    return UserDefaults.standard.bool(forKey: Preference.Key.quitWhenNoOpenedWindow)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplicationTerminateReply {
    playerCore.terminateMPV()
    return .terminateNow
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows
    flag: Bool) -> Bool {
    if !flag && UserDefaults.standard.bool(forKey: Preference.Key.openStartPanel) {
      self.openFile(sender)
    }
    return true
  }

  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    if !isReady {
      UserDefaults.standard.register(defaults: Preference.defaultPreference)
      playerCore.startMPV()
      menuController.bindMenuItems()
      isReady = true
    }

    let url = URL(fileURLWithPath: filename)
    if playerCore.ud.bool(forKey: Preference.Key.recordRecentFiles) {
      NSDocumentController.shared().noteNewRecentDocumentURL(url)
    }
    playerCore.openFile(url)
    return true
  }

  // MARK: - Dock menu

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    return dockMenu
  }


  // MARK: - URL Scheme

  func handleURLEvent(event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
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
      playerCore.openURLString(urlValue)
    }
  }

  // MARK: - Menu actions

  @IBAction func openFile(_ sender: AnyObject) {
    let panel = NSOpenPanel()
    panel.title = "Choose media file"
    panel.canCreateDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.resolvesAliases = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == NSFileHandlingPanelOKButton {
      if let url = panel.url {
        if playerCore.ud.bool(forKey: Preference.Key.recordRecentFiles) {
          NSDocumentController.shared().noteNewRecentDocumentURL(url)
        }
        playerCore.openFile(url)
      }
    }
  }

  @IBAction func openURL(_ sender: NSMenuItem) {
    let panel = NSAlert()
    panel.messageText = "Open URL"
    panel.informativeText = "Please enter the URL:"
    let inputViewController = OpenURLAccessoryViewController()
    panel.accessoryView = inputViewController.view
    panel.addButton(withTitle: "OK")
    panel.addButton(withTitle: "Cancel")
    panel.window.initialFirstResponder = inputViewController.urlField
    let response = panel.runModal()
    if response == NSAlertFirstButtonReturn {
      if let url = inputViewController.url {
        playerCore.openURL(url)
      } else {
        Utility.showAlert("wrong_url_format")
      }
    }
  }

  @IBAction func menuOpenScreenshotFolder(_ sender: NSMenuItem) {
    let screenshotPath = UserDefaults.standard.string(forKey: Preference.Key.screenshotFolder)!
    let absoluteScreenshotPath = NSString(string: screenshotPath).expandingTildeInPath
    let url = URL(fileURLWithPath: absoluteScreenshotPath, isDirectory: true)
      NSWorkspace.shared().open(url)
  }

  @IBAction func menuSelectAudioDevice(_ sender: NSMenuItem) {
    if let name = sender.representedObject as? String {
      PlayerCore.shared.setAudioDevice(name)
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

  @IBAction func helpAction(_ sender: AnyObject) {
    NSWorkspace.shared().open(URL(string: AppData.wikiLink)!)
  }

  @IBAction func githubAction(_ sender: AnyObject) {
    NSWorkspace.shared().open(URL(string: AppData.githubLink)!)
  }

  @IBAction func websiteAction(_ sender: AnyObject) {
    NSWorkspace.shared().open(URL(string: AppData.websiteLink)!)
  }

  @IBAction func checkUpdate(_ sender: AnyObject) {
    UpdateChecker.checkUpdate()
  }


}
