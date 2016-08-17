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
  
  lazy var playerController: PlayerController! = PlayerController()

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    UserDefaults.standard.register(Preference.defaultPreference)
    playerController.startMPV()
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
    playerController.terminateMPV()
    return .terminateNow
  }
  
  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    playerController.openFile(URL(fileURLWithPath: filename))
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
        playerController.openFile(url)
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
