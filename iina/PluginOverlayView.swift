//
//  PluginOverlayView.swift
//  iina
//
//  Created by Collider LI on 21/1/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Cocoa
import WebKit

class PluginOverlayView: WKWebView, WKNavigationDelegate {
  weak private var pluginInstance: JavascriptPluginInstance!

  var isClickable = false

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard isClickable else {
      return nil
    }

    var clickable = false
    var finished = false
    let x = point.x
    let y = self.frame.height - point.y
    
    evaluateJavaScript("window.iina._hitTest(\(x),\(y))") { (result, error) in
      if let result = result as? Bool {
        clickable = result
      }
      finished = true
    }

    while !finished {
      RunLoop.current.run(mode: .default, before: NSDate.distantFuture)
    }
    if clickable {
      return super.hitTest(point)
    }
    return nil
  }

  deinit {
    configuration.userContentController.removeScriptMessageHandler(forName: "iina")
  }

  func attachTo(windowController: MainWindowController) {
    windowController.pluginOverlayViewContainer.addSubview(self)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": self])
  }

  static func create(pluginInstance: JavascriptPluginInstance) -> PluginOverlayView {
    let config = WKWebViewConfiguration()
    config.userContentController.addUserScript(
      WKUserScript(source: JavascriptMessageHub.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )
    config.userContentController.addUserScript(
      WKUserScript(source: hitTestScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    )

    config.userContentController.add(pluginInstance.apis!["overlay"] as! WKScriptMessageHandler, name: "iina")

    let webView = PluginOverlayView(frame: .zero, configuration: config)
    webView.pluginInstance = pluginInstance
    webView.navigationDelegate = webView
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.setValue(false, forKey: "drawsBackground")
    webView.isHidden = true

    return webView
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if let url = navigationAction.request.url, pluginInstance.canAccess(url: url) {
      decisionHandler(.cancel)
    } else {
      decisionHandler(.allow)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!){
    if let wc = window?.windowController as? PlayerWindowController {
      wc.player.events.emit(.pluginOverlayLoaded)
    }
  }
}


fileprivate let hitTestScript = """
window.iina._hitTest = function(x, y) {
  return !!document.elementFromPoint(x, y).dataset.hasOwnProperty("clickable")
}
"""
