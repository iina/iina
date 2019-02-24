//
//  JavascriptAPIOverlay.swift
//  iina
//
//  Created by Collider LI on 24/2/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIOverlayExportable: JSExport {
  func show()
  func hide()
  func loadFile(_ path: String)
}

class JavascriptAPIOverlay: JavascriptAPI, JavascriptAPIOverlayExportable {
  @objc func show() {
    guard player.mainWindow.isWindowLoaded else { return }
    DispatchQueue.main.async {
      self.player.mainWindow.pluginOverlayView.isHidden = false
    }
  }

  @objc func hide() {
    guard player.mainWindow.isWindowLoaded else { return }
    DispatchQueue.main.async {
      self.player.mainWindow.pluginOverlayView.isHidden = true
    }
  }

  @objc func loadFile(_ path: String) {
    guard player.mainWindow.isWindowLoaded else {
      throwError(withMessage: "overlay.loadFile called when window is not available. Please place it after received event iina.window-loaded.")
      return
    }
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    player.mainWindow.pluginOverlayView.loadFileURL(url, allowingReadAccessTo: rootURL)
  }
}
