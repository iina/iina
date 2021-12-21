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
  func postMessage(_ name: String, _ data: JSValue)
  func onMessage(_ name: String, _ callback: JSValue)
  func setProperty(_ properties: JSValue)
}

class JavascriptAPIStandaloneWindow: JavascriptAPI, JavascriptAPIStandaloneWindowExportable, WKScriptMessageHandler {
  private lazy var messageHub = JavascriptMessageHub(reference: self)

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    guard instance.standaloneWindowCreated else { return }
    executeOnMainThread {
      instance.standaloneWindow.close()
    }
  }

  func close() {
    executeOnMainThread {
      pluginInstance.standaloneWindow.close()
    }
  }

  func open() {
    executeOnMainThread {
      pluginInstance.standaloneWindow.makeKeyAndOrderFront(nil)
    }
  }

  func loadFile(_ path: String) {
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    executeOnMainThread {
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
          executeOnMainThread {
            window.title = title + " — \(pluginInstance.plugin.name)"
          }
        }
      case "resizable":
        executeOnMainThread {
          setStyleMask(.resizable, value)
        }
      case "fullSizeContentView":
        executeOnMainThread {
          setStyleMask(.fullSizeContentView, value)
        }
      default:
        break
      }
    }
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    messageHub.receiveMessageFromUserContentController(message)
  }
}
