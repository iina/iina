//
//  JavascriptAPISidebarView.swift
//  iina
//
//  Created by Collider LI on 11/10/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore
import WebKit


@objc protocol JavascriptAPISidebarViewExportable: JSExport {
  func loadFile(_ path: String)
  func show()
  func hide()
  func sendMessage(_ name: String, _ data: JSValue)
  func onMessage(_ name: String, _ callback: JSValue)
}

class JavascriptAPISidebarView: JavascriptAPI, JavascriptAPISidebarViewExportable, WKScriptMessageHandler {
  private var listeners: [String: JSManagedValue] = [:]

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    listeners.removeAll()
  }

  func loadFile(_ path: String) {
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    pluginInstance.sidebarTabView.load(URLRequest(url: url))
  }

  func show() {
    let id = pluginInstance.plugin.identifier
    player.mainWindow.showSettingsSidebar(tab: .plugin(id: id), force: true, hideIfAlreadyShown: false)
  }

  func hide() {
    player.mainWindow.hideSideBar()
  }

  func sendMessage(_ name: String, _ data: JSValue) {
    DispatchQueue.main.async {
      let webView = self.pluginInstance.sidebarTabView
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
