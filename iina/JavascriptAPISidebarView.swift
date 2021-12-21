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
    player!.mainWindow.quickSettingView.removePluginTab(withIdentifier: instance.plugin.identifier)
  }

  func loadFile(_ path: String) {
    let rootURL = pluginInstance.plugin.root
    let url = rootURL.appendingPathComponent(path)
    executeOnMainThread {
      pluginInstance.sidebarTabView.load(URLRequest(url: url))
    }
  }

  func show() {
    let id = pluginInstance.plugin.identifier
    player!.mainWindow.showSettingsSidebar(tab: .plugin(id: id), force: true, hideIfAlreadyShown: false)
  }

  func hide() {
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
