//
//  JavascriptAPICore.swift
//  iina
//
//  Created by Collider LI on 11/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPICoreExportable: JSExport {
  func open(_ url: String)
  func osd(_ message: String)
  func getWindowFrame() -> JSValue
  func loadVideoTrack(_ filename: String)
  func loadAudioTrack(_ filename: String)
  func loadSubtitle(_ filename: String)
}

class JavascriptAPICore: JavascriptAPI, JavascriptAPICoreExportable {
  @objc func open(_ url: String) {
    self.player.openURLString(url)
  }

  @objc func osd(_ message: String) {
    whenPermitted(to: .showOSD) {
      self.player.sendOSD(.customWithDetail(message, "From plugin \(pluginInstance.plugin.name)"),
                          autoHide: true, accessoryView: nil, external: true)
    }
  }

  @objc func getWindowFrame() -> JSValue {
    guard let frame = player.mainWindow.window?.frame else { return JSValue(undefinedIn: context) }
    return JSValue(rect: frame, in: context)
  }
  
  @objc func loadVideoTrack(_ filename: String) {
    guard let dir = JavascriptAPIFile.currentDir(player) else { return }
    player.loadExternalVideoFile(dir.appendingPathComponent(filename, isDirectory: false))
  }
  
  @objc func loadAudioTrack(_ filename: String) {
    guard let dir = JavascriptAPIFile.currentDir(player) else { return }
    player.loadExternalAudioFile(dir.appendingPathComponent(filename, isDirectory: false))
  }

  @objc func loadSubtitle(_ filename: String) {
    guard let dir = JavascriptAPIFile.currentDir(player) else { return }
    player.loadExternalSubFile(dir.appendingPathComponent(filename, isDirectory: false))
  }
}
