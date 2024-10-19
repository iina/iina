//
//  PluginOverlayView.swift
//  iina
//
//  Created by Collider LI on 21/1/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Cocoa
@preconcurrency import WebKit

class PluginOverlayView: WKWebView, WKNavigationDelegate {
  weak private var pluginInstance: JavascriptPluginInstance!

  var isEnteringSimpleMode = false
  private var pendingStyle: String?
  private var pendingContent: String?

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
    Utility.executeOnMainThread {
      let config = WKWebViewConfiguration()
      config.userContentController.addUserScript(
        WKUserScript(source: JavascriptMessageHub.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
      )
      config.userContentController.addUserScript(
        WKUserScript(source: hitTestScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
      )

      config.userContentController.add(pluginInstance.apis!["overlay"] as! WKScriptMessageHandler, name: "iina")

      let webView = PluginOverlayView(frame: .zero, configuration: config)
      if #available(macOS 13.3, *) {
        webView.isInspectable = true
      }
      webView.pluginInstance = pluginInstance
      webView.navigationDelegate = webView
      webView.translatesAutoresizingMaskIntoConstraints = false
      webView.setValue(false, forKey: "drawsBackground")
      webView.isHidden = true
      return webView
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if let url = navigationAction.request.url, pluginInstance.canAccess(url: url) {
      decisionHandler(.cancel)
    } else {
      decisionHandler(.allow)
    }
  }

  // MARK: Simple mode

  func setSimpleModeStyle(_ style: String) {
    if isEnteringSimpleMode {
      pendingStyle = style
    } else {
      _simpleModeSetStyle(style)
    }
  }

  func setSimpleModeContent(_ content: String) {
    if isEnteringSimpleMode {
      pendingContent = content
    } else {
      _simpleModeSetContent(content)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!){
    if let wc = window?.windowController as? PlayerWindowController {
      wc.player.events.emit(.pluginOverlayLoaded)
    }

    guard isEnteringSimpleMode else { return }
    isEnteringSimpleMode = false

    if let style = pendingStyle {
      _simpleModeSetStyle(style)
    }
    if let content = pendingContent {
      _simpleModeSetContent(content)
    }
  }

  private func _simpleModeSetStyle(_ style: String) {
    Utility.executeOnMainThread {
      evaluateJavaScript("window.iina._simpleModeSetStyle(`\(style)`)") { (_, error) in
        if let error = error {
          Logger.log(error.localizedDescription, level: .error, subsystem: self.pluginInstance.subsystem)
        }
      }
    }
  }

  private func _simpleModeSetContent(_ content: String) {
    Utility.executeOnMainThread {
      evaluateJavaScript("window.iina._simpleModeSetContent(`\(content)`)") { (_, error) in
        if let error = error {
          Logger.log(error.localizedDescription, level: .error, subsystem: self.pluginInstance.subsystem)
        }
      }
    }
  }
}


fileprivate let hitTestScript = """
window.iina._hitTest = function(x, y) {
  return !!document.elementFromPoint(x, y).dataset.hasOwnProperty("clickable")
}
"""
