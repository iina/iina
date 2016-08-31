//
//  AppDelegate.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  
  lazy var playerCore: PlayerCore = PlayerCore.shared
  
  @IBOutlet weak var menuController: MenuController!

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    UserDefaults.standard.register(defaults: Preference.defaultPreference)
    playerCore.startMPV()
    menuController.bindMenuItems()
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }
  
  func applicationDidResignActive(_ notification: Notification) {
//    if NSApp.mainWindow == nil && NSApp.keyWindow == nil {
//      NSApp.terminate(self)
//    }
  }
  
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
  
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplicationTerminateReply {
    playerCore.terminateMPV()
    return .terminateNow
  }
  
  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    playerCore.openFile(URL(fileURLWithPath: filename))
    return true
  }
  
  // MARK: - Menu
  
  @IBAction func openFile(_ sender: NSMenuItem) {
    let panel = NSOpenPanel()
    panel.title = "Choose media file"
    panel.canCreateDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.resolvesAliases = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == NSFileHandlingPanelOKButton {
      if let url = panel.url {
        playerCore.openFile(url)
      }
    }
  }
  
  @IBAction func menuOpenScreenshotFolder(_ sender: NSMenuItem) {
    let screenshotPath = UserDefaults.standard.string(forKey: Preference.Key.screenshotFolder)!
    let absoluteScreenshotPath = NSString(string: screenshotPath).expandingTildeInPath
    let url = URL(fileURLWithPath: absoluteScreenshotPath, isDirectory: true)
      NSWorkspace.shared().open(url)
  }
  
}
