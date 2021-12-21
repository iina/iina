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
  func postMessage(_ name: String, _ data: JSValue)
  func onMessage(_ name: String, _ callback: JSValue)
}

class JavascriptAPIOverlay: JavascriptAPI, JavascriptAPIOverlayExportable, WKScriptMessageHandler {
  private lazy var messageHub = JavascriptMessageHub(reference: self)
  private var inSimpleMode = false

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    guard instance.overlayViewLoaded else { return }
    instance.overlayView.removeFromSuperview()
  }

  func show() {
    guard pluginInstance != nil else { return }
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.isHidden = false
    }
  }

  func hide() {
    guard pluginInstance != nil else { return }
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.isHidden = true
    }
  }

  func setOpacity(_ opacity: Float) {
    guard pluginInstance != nil else { return }
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
    DispatchQueue.main.async {
      self.pluginInstance.overlayView.alphaValue = CGFloat(opacity)
    }
  }

  func loadFile(_ path: String) {
    guard player!.mainWindow.isWindowLoaded && permitted(to: .displayVideoOverlay) else {
      throwError(withMessage: "overlay.loadFile called when window is not available. Please call it after receiving the \"iina.window-loaded\" event.")
      return
    }
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    executeOnMainThread {
      pluginInstance.overlayView.loadFileURL(url, allowingReadAccessTo: rootURL)
      pluginInstance.overlayViewLoaded = true
      inSimpleMode = false
    }
  }

  func simpleMode() {
    guard player!.mainWindow.isWindowLoaded && permitted(to: .displayVideoOverlay) else {
      throwError(withMessage: "overlay.simpleMode called when window is not available. Please call it after receiving the \"iina.window-loaded\" event.")
      return
    }
    if (inSimpleMode) { return }
    pluginInstance.overlayView.loadHTMLString(simpleModeHTMLString, baseURL: nil)
    pluginInstance.overlayViewLoaded = true
    inSimpleMode = true
  }

  func setStyle(_ style: String) {
    guard pluginInstance != nil else { return }
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
    guard pluginInstance != nil else { return }
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

  func postMessage(_ name: String, _ data: JSValue) {
    guard pluginInstance != nil else { return }
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
    messageHub.postMessage(to: pluginInstance.overlayView, name: name, data: data)
  }

  func onMessage(_ name: String, _ callback: JSValue) {
    guard pluginInstance != nil else { return }
    guard pluginInstance.overlayViewLoaded && permitted(to: .displayVideoOverlay) else { return }
    messageHub.addListener(forEvent: name, callback: callback)
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    messageHub.receiveMessageFromUserContentController(message)
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
