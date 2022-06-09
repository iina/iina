//
//  JavascriptAPIStandaloneWindow.swift
//  iina
//
//  Created by Collider LI on 2/9/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore
import WebKit

@objc protocol JavascriptAPIStandaloneWindowExportable: JSExport {
  func open()
  func close()
  func isOpen() -> Bool
  func loadFile(_ path: String)
  func simpleMode()
  func setStyle(_ style: String)
  func setContent(_ content: String)
  func postMessage(_ name: String, _ data: JSValue)
  func onMessage(_ name: String, _ callback: JSValue)
  func setProperty(_ properties: JSValue)
  func setFrame(_ w: JSValue, _ h: JSValue, _ x: JSValue, _ y: JSValue)
}

class JavascriptAPIStandaloneWindow: JavascriptAPI, JavascriptAPIStandaloneWindowExportable, WKScriptMessageHandler {
  private lazy var messageHub = JavascriptMessageHub(reference: self)
  private var inSimpleMode = false

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    guard instance.standaloneWindowCreated else { return }
    Utility.executeOnMainThread {
      instance.standaloneWindow.close()
    }
  }

  func close() {
    Utility.executeOnMainThread {
      pluginInstance.standaloneWindow.close()
    }
  }

  func open() {
    Utility.executeOnMainThread {
      pluginInstance.standaloneWindow.makeKeyAndOrderFront(nil)
    }
  }

  func isOpen() -> Bool {
    return pluginInstance.standaloneWindowCreated && Utility.executeOnMainThread {
       pluginInstance.standaloneWindow.isVisible
    }
  }

  func simpleMode() {
    Utility.executeOnMainThread {
      pluginInstance.standaloneWindow.isEnteringSimpleMode = true
      pluginInstance.standaloneWindow.webView.loadHTMLString(simpleModeHTMLString, baseURL: nil)
    }
    inSimpleMode = true
  }

  func loadFile(_ path: String) {
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    inSimpleMode = false
    Utility.executeOnMainThread {
      pluginInstance.standaloneWindow.webView.loadFileURL(url, allowingReadAccessTo: rootURL)
    }
  }

  func postMessage(_ name: String, _ data: JSValue) {
    guard pluginInstance.standaloneWindowCreated else { return }
    messageHub.postMessage(to: pluginInstance.standaloneWindow.webView, name: name, data: data)
  }

  func onMessage(_ name: String, _ callback: JSValue) {
    messageHub.addListener(forEvent: name, callback: callback)
  }

  func setStyle(_ style: String) {
    guard pluginInstance != nil else { return }
    guard inSimpleMode else {
      log("standaloneWindow.setStyle is only available in simple mode.", level: .error)
      return
    }
    pluginInstance.standaloneWindow.setSimpleModeStyle(style)
  }

  func setContent(_ content: String) {
    guard pluginInstance != nil else { return }
    guard inSimpleMode else {
      log("standaloneWindow.setContent is only available in simple mode.", level: .error)
      return
    }
    pluginInstance.standaloneWindow.setSimpleModeContent(content)
  }

  func setProperty(_ properties: JSValue) {
    guard pluginInstance.standaloneWindowCreated,
      let dict = properties.toObject() as? [String: Any] else { return }
    let window = pluginInstance.standaloneWindow;
    func setStyleMask(_ mask: NSWindow.StyleMask, _ value: Any) {
      guard let boolValue = value as? Bool else { return }
      if boolValue {
        window.styleMask.insert(mask)
      } else {
        window.styleMask.remove(mask)
      }
    }

    for (key, value) in dict {
      switch key {
      case "title":
        if let title = value as? String {
          Utility.executeOnMainThread {
            window.title = title + " — \(pluginInstance.plugin.name)"
          }
        }
      case "resizable":
        Utility.executeOnMainThread {
          setStyleMask(.resizable, value)
        }
      case "fullSizeContentView":
        Utility.executeOnMainThread {
          setStyleMask(.fullSizeContentView, value)
        }
      case "hideTitleBar":
        let boolVal = (value as? Bool == true)
        Utility.executeOnMainThread {
          window.titlebarAppearsTransparent = boolVal
          window.titleVisibility = boolVal ? .hidden : .visible
          window.isMovableByWindowBackground = boolVal
        }
      default:
        break
      }
    }
  }

  func setFrame(_ w: JSValue, _ h: JSValue, _ x: JSValue, _ y: JSValue) {
    // we need to get the values on current thread
    let w = w.isNumber ? CGFloat(w.toDouble()) : nil
    let h = h.isNumber ? CGFloat(h.toDouble()) : nil
    let x = x.isNumber ? CGFloat(x.toDouble()) : nil
    let y = y.isNumber ? CGFloat(y.toDouble()) : nil
    Utility.executeOnMainThread {
      let window = pluginInstance.standaloneWindow;
      let rect = NSRect(x: x ?? window.frame.origin.x,
                        y: y ?? window.frame.origin.y,
                        width: w ?? window.frame.width,
                        height: h ?? window.frame.height)
      window.setFrame(rect, display: true)
    }
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
    }

    @media (prefers-color-scheme: dark) {
      body {
        color: #eee;
      }
      body a {
        color: #007aff;
      }
    }
  </style>
  <style id="style"></style>
</head>

<body>
  <div id="content"></div>
</body>

</html>
"""
