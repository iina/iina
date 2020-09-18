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
  private var listeners: [String: JSManagedValue] = [:]
  private var inSimpleMode = false

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    guard instance.overlayViewLoaded else { return }
    instance.overlayView.removeFromSuperview()
  }

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
      throwError(withMessage: "overlay.loadFile called when window is not available. Please call it after receiving the \"iina.window-loaded\" event.")
      return
    }
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    pluginInstance.overlayView.loadFileURL(url, allowingReadAccessTo: rootURL)
    pluginInstance.overlayViewLoaded = true
    inSimpleMode = false
  }

  func simpleMode() {
    guard player.mainWindow.isWindowLoaded && permitted(to: .displayVideoOverlay) else {
      throwError(withMessage: "overlay.simpleMode called when window is not available. Please call it after receiving the \"iina.window-loaded\" event.")
      return
    }
    if (inSimpleMode) { return }
    pluginInstance.overlayView.loadHTMLString(simpleModeHTMLString, baseURL: nil)
    pluginInstance.overlayViewLoaded = true
    inSimpleMode = true
  }

  func setStyle(_ style: String) {
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
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
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
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
      let webView = self.pluginInstance.overlayView
      guard let object = data.toObject(),
         let data = try? JSONSerialization.data(withJSONObject: object),
         let dataString = String(data: data, encoding: .utf8) else {
          webView.evaluateJavaScript("window.iina._emit(`\(name)`)")
          return
      }
      webView.evaluateJavaScript("window.iina._emit(`\(name)`, `\(dataString)`)")
    }
  }

  func onMessage(_ name: String, _ callback: JSValue) {
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
    if let previousCallback = listeners[name] {
      JSContext.current()!.virtualMachine.removeManagedReference(previousCallback, withOwner: self)
    }
    let managed = JSManagedValue(value: callback)
    listeners[name] = managed
    JSContext.current()!.virtualMachine.addManagedReference(managed, withOwner: self)
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let dict = message.body as? [Any], dict.count == 2,
      let name = dict[0] as? String,
      let callback = listeners[name] else { return }

    guard let dataString = dict[1] as? String,
      let data = dataString.data(using: .utf8),
      let decoded = try? JSONSerialization.jsonObject(with: data) else {
        callback.value.call(withArguments: [])
      return
    }

    callback.value.call(withArguments: [JSValue(object: decoded, in: pluginInstance.js) ?? NSNull()])
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
        font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
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
