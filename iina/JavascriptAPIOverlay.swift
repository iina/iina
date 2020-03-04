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
  func simpleMode()
  func setStyle(_ style: String)
  func setContent(_ content: String)
  func sendMessage(_ name: String, _ data: JSValue)
  func onMessage(_ name: String, _ callback: JSValue)
}

class JavascriptAPIOverlay: JavascriptAPI, JavascriptAPIOverlayExportable, WKScriptMessageHandler {
  private var listeners: [String: JSValue] = [:]
  private var inSimpleMode = false

  func show() {
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.isHidden = false
    }
  }

  func hide() {
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.isHidden = true
    }
  }

  func setOpacity(_ opacity: Float) {
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.alphaValue = CGFloat(opacity)
    }
  }

  func loadFile(_ path: String) {
    guard player.mainWindow.isWindowLoaded && permitted(to: .displayVideoOverlay) else {
      throwError(withMessage: "overlay.loadFile called when window is not available. Please call it after receiving event \"iina.window-loaded\".")
      return
    }
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    pluginInstance.overlayView.loadFileURL(url, allowingReadAccessTo: rootURL)
    pluginInstance.overlayViewLoaded = true
    inSimpleMode = false
  }

  func simpleMode() {
    pluginInstance.overlayView.loadHTMLString(simpleModeHTMLString, baseURL: nil)
    pluginInstance.overlayViewLoaded = true
    inSimpleMode = true
  }

  func setStyle(_ style: String) {
    guard inSimpleMode else {
      log("overlay.setStyle is only available in simple mode.", level: .error)
      return
    }
    pluginInstance.overlayView.evaluateJavaScript("window.iina._simpleModeSetStyle(`\(style)`)") { (_, error) in
      if let error = error {
        self.log(error.localizedDescription, level: .error)
      }
    }
  }

  func setContent(_ content: String) {
    guard inSimpleMode else {
      log("overlay.setContent is only available in simple mode.", level: .error)
      return
    }
    pluginInstance.overlayView.evaluateJavaScript("window.iina._simpleModeSetContent(`\(content)`)") { (_, error) in
      if let error = error {
        self.log(error.localizedDescription, level: .error)
      }
    }
  }

  func sendMessage(_ name: String, _ data: JSValue) {
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.evaluateJavaScript("window.iina._emit(`\(name)`, \(data))")
    }
  }

  func onMessage(_ name: String, _ callback: JSValue) {
    listeners[name] = callback
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let dict = message.body as? [Any], dict.count == 2 else { return }
    guard let name = dict[0] as? String else { return }
    let data = dict[1]
    guard let callback = listeners[name] else { return }
    callback.call(withArguments: [JSValue(object: data, in: pluginInstance.js)!])
  }
}


fileprivate let simpleModeHTMLString = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Overlay</title>
    <style>
    body {
        font-size: 13px;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
        color: white;
        text-shadow: 0 1px 0 black, 0 -1px 0 black, -1px 0 0 black, 1px 0 0 black;
    }
    </style>
    <style id="style"></style>
</head>
<body>
    <div id="content"></div>
</body>
</html>
"""
