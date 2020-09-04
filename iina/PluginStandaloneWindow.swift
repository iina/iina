//
//  PluginStandaloneWindow.swift
//  iina
//
//  Created by Collider LI on 2/9/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa
import WebKit

class PluginStandaloneWindow: NSWindow {
  var webView: WKWebView!

  static func create(pluginInstance: JavascriptPluginInstance) -> PluginStandaloneWindow {
    let rect = NSRect(x: 0, y: 0, width: 600, height: 400)
    let window = PluginStandaloneWindow(contentRect: rect,
                                        styleMask: [.closable, .resizable, .titled],
                                        backing: .buffered,
                                        defer: false)
    window.title = "Window — \(pluginInstance.plugin.name)"
    window.isReleasedWhenClosed = false
    window.center()
    window.initializeWebView(pluginInstance: pluginInstance)
    return window
  }

  deinit {
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "iina")
  }

  func initializeWebView(pluginInstance: JavascriptPluginInstance) {
    let config = WKWebViewConfiguration()
    config.userContentController.addUserScript(
      WKUserScript(source: IINAJavascriptPluginBridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )

    config.userContentController.add(pluginInstance.apis!["standaloneWindow"] as! WKScriptMessageHandler, name: "iina")

    webView = WKWebView(frame: .zero, configuration: config)
    webView.translatesAutoresizingMaskIntoConstraints = false
    contentView?.addSubview(webView)
    Utility.quickConstraints(["H:|-0-[v]-0-|", "V:|-0-[v]-0-|"], ["v": webView])
  }
}

