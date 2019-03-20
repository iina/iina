//
//  JavascriptAPIOverlay.swift
//  iina
//
//  Created by Collider LI on 24/2/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore
import WebKit

@objc protocol JavascriptAPIOverlayExportable: JSExport {
  func show()
  func hide()
  func setOpacity(_ opacity: Float)
  func loadFile(_ path: String)
  func sendMessage(_ name: String, _ data: JSValue)
  func onMessage(_ name: String, _ callback: JSValue)
}

class JavascriptAPIOverlay: JavascriptAPI, JavascriptAPIOverlayExportable, WKScriptMessageHandler {
  private var listeners: [String: JSValue] = [:]

  @objc func show() {
    guard pluginInstance.overlayViewLoaded && permitted(to: .videoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.isHidden = false
    }
  }

  @objc func hide() {
    guard pluginInstance.overlayViewLoaded && permitted(to: .videoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.isHidden = true
    }
  }

  @objc func setOpacity(_ opacity: Float) {
    guard pluginInstance.overlayViewLoaded && permitted(to: .videoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.alphaValue = CGFloat(opacity)
    }
  }

  @objc func loadFile(_ path: String) {
    guard player.mainWindow.isWindowLoaded && permitted(to: .videoOverlay) else {
      throwError(withMessage: "overlay.loadFile called when window is not available. Please call it after receiving event \"iina.window-loaded\".")
      return
    }
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    pluginInstance.overlayView.loadFileURL(url, allowingReadAccessTo: rootURL)
    pluginInstance.overlayViewLoaded = true
  }

  @objc func sendMessage(_ name: String, _ data: JSValue) {
    guard pluginInstance.overlayViewLoaded && permitted(to: .videoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.evaluateJavaScript("window.iina._emit(`\(name)`, \(data))")
    }
  }

  @objc func onMessage(_ name: String, _ callback: JSValue) {
    listeners[name] = callback
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let dict = message.body as? [Any], dict.count == 2 else { return }
    guard let name = dict[0] as? String else { return }
    let data = dict[1]
    guard let callback = listeners[name] else { return }
    callback.call(withArguments: [JSValue(object: data, in: pluginInstance.js)])
  }
}
