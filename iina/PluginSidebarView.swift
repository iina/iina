//
//  PluginSidebarView.swift
//  iina
//
//  Created by Collider LI on 11/10/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa
import WebKit

class PluginSidebarView: WKWebView, WKNavigationDelegate {
  deinit {
    configuration.userContentController.removeScriptMessageHandler(forName: "iina")
  }

  static func create(pluginInstance: JavascriptPluginInstance) -> PluginSidebarView {
    let config = WKWebViewConfiguration()
    config.userContentController.addUserScript(
      WKUserScript(source: JavascriptMessageHub.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )

    config.userContentController.add(pluginInstance.apis!["sidebar"] as! WKScriptMessageHandler, name: "iina")

    let webView = PluginSidebarView(frame: .zero, configuration: config)
    webView.navigationDelegate = webView
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.setValue(false, forKey: "drawsBackground")

    return webView
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!){
    if let wc = window?.windowController as? PlayerWindowController {
      wc.player.events.emit(.pluginOverlayLoaded)
    }
  }
}
