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
  func loadFile(_ path: String)
  func sendMessage(_ name: String, _ data: JSValue)
  func onMessage(_ name: String, _ callback: JSValue)
  func setProperty(_ properties: JSValue)
}

class JavascriptAPIStandaloneWindow: JavascriptAPI, JavascriptAPIStandaloneWindowExportable, WKScriptMessageHandler {
  private var listeners: [String: JSValue] = [:]

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    listeners.removeAll()
    guard instance.standaloneWindowCreated else { return }
    instance.standaloneWindow.close()
  }

  func close() {
    pluginInstance.standaloneWindow.close()
  }

  func open() {
    pluginInstance.standaloneWindow.makeKeyAndOrderFront(nil)
  }

  func loadFile(_ path: String) {
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    pluginInstance.standaloneWindow.webView.loadFileURL(url, allowingReadAccessTo: rootURL)
  }

  func sendMessage(_ name: String, _ data: JSValue) {
    guard pluginInstance.standaloneWindowCreated else { return }
    DispatchQueue.main.async {
      guard let webView = self.pluginInstance.standaloneWindow.webView else { return }
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
    if let previousCallback = listeners[name] {
      JSContext.current()!.virtualMachine.removeManagedReference(previousCallback, withOwner: self)
    }
    JSContext.current()!.virtualMachine.addManagedReference(callback, withOwner: self)
    listeners[name] = callback
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
          window.title = title + " — \(pluginInstance.plugin.name)"
        }
      case "resizable":
        setStyleMask(.resizable, value)
      case "fullSizeContentView":
        setStyleMask(.fullSizeContentView, value)
      default:
        break
      }
    }
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let dict = message.body as? [Any], dict.count == 2,
      let name = dict[0] as? String,
      let callback = listeners[name] else { return }

    guard let dataString = dict[1] as? String,
      let data = dataString.data(using: .utf8),
      let decoded = try? JSONSerialization.jsonObject(with: data) else {
        callback.call(withArguments: [])
      return
    }

    callback.call(withArguments: [JSValue(object: decoded, in: pluginInstance.js) ?? NSNull()])
  }
}
