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
    player!.mainWindow.pluginView.removePluginTab(withIdentifier: instance.plugin.identifier)
  }

  func loadFile(_ path: String) {
    guard player!.mainWindow.loaded else {
      throwError(withMessage: "sidebar.loadFile called when window is not available. Please call it after receiving the \"iina.window-loaded\" event.")
      return
    }
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    Utility.executeOnMainThread {
      let nav = pluginInstance.sidebarTabView.load(URLRequest(url: url))
      if nav == nil {
        throwError(withMessage: "Failed to load ")
      }
    }
    messageHub.clearListeners()
  }

  func show() {
    guard player!.mainWindow.loaded else {
      throwError(withMessage: "sidebar.show called when window is not available. Please call it after receiving the \"iina.window-loaded\" event.")
      return
    }
    let id = pluginInstance.plugin.identifier
    player!.mainWindow.showPluginSidebar(tab: id, force: true, hideIfAlreadyShown: false)
  }

  func hide() {
    guard player!.mainWindow.loaded else {
      throwError(withMessage: "sidebar.hide called when window is not available. Please call it after receiving the \"iina.window-loaded\" event.")
      return
    }
    player!.mainWindow.hideSideBar()
  }

  func postMessage(_ name: String, _ data: JSValue) {
    messageHub.postMessage(to: pluginInstance.sidebarTabView, name: name, data: data)
  }

  func onMessage(_ name: String, _ callback: JSValue) {
    messageHub.addListener(forEvent: name, callback: callback)
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    messageHub.receiveMessageFromUserContentController(message)
  }
}
