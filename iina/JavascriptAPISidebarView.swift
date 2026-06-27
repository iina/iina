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
  func postMessage(_ name: String, _ data: JSValue)
  func onMessage(_ name: String, _ callback: JSValue)
}

class JavascriptAPISidebarView: JavascriptAPI, JavascriptAPISidebarViewExportable, WKScriptMessageHandler {
  private lazy var messageHub = JavascriptMessageHub(reference: self)

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    // removePluginTab is not called here to avoid exclusivity conflicts during deinit.
    // reloadPlugin (called after clearPlugins) will trigger updatePluginTabs to refresh
    // the tab list, automatically removing stale tabs.
  }

  func loadFile(_ path: String) {
    guard let instance = pluginInstance else { return }
    guard player!.mainWindow.loaded else {
      throwError(withMessage: "sidebar.loadFile called when window is not available. Please call it after receiving the \"iina.window-loaded\" event.")
      return
    }
    let rootURL = instance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    Utility.executeOnMainThread {
      let nav = instance.sidebarTabView.load(URLRequest(url: url))
      if nav == nil {
        throwError(withMessage: "Failed to load ")
      }
    }
    messageHub.clearListeners()
  }

  func show() {
    guard let instance = pluginInstance else { return }
    guard player!.mainWindow.loaded else {
      throwError(withMessage: "sidebar.show called when window is not available. Please call it after receiving the \"iina.window-loaded\" event.")
      return
    }
    let id = instance.plugin.identifier
    player!.mainWindow.sidebars.show(sidebar: .plugins, tab: id, force: true, hideIfAlreadyShown: false)
  }

  func hide() {
    guard player!.mainWindow.loaded else {
      throwError(withMessage: "sidebar.hide called when window is not available. Please call it after receiving the \"iina.window-loaded\" event.")
      return
    }
    player!.mainWindow.sidebars.hide(.plugins)
  }

  func postMessage(_ name: String, _ data: JSValue) {
    guard let instance = pluginInstance else { return }
    messageHub.postMessage(to: instance.sidebarTabView, name: name, data: data)
  }

  func onMessage(_ name: String, _ callback: JSValue) {
    messageHub.addListener(forEvent: name, callback: callback)
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    messageHub.receiveMessageFromUserContentController(message)
  }
}
