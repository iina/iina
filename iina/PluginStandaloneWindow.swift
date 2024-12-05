//
//  PluginStandaloneWindow.swift
//  iina
//
//  Created by Collider LI on 2/9/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa
@preconcurrency import WebKit

class PluginStandaloneWindow: NSWindow, WKNavigationDelegate, WKUIDelegate {
  weak private var pluginInstance: JavascriptPluginInstance!
  var webView: WKWebView!

  var isEnteringSimpleMode = false
  private var pendingStyle: String?
  private var pendingContent: String?

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
    self.pluginInstance = pluginInstance

    Utility.executeOnMainThread { 
      let config = WKWebViewConfiguration()
      config.userContentController.addUserScript(
        WKUserScript(source: JavascriptMessageHub.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
      )

      config.userContentController.add(pluginInstance.apis!["standaloneWindow"] as! WKScriptMessageHandler, name: "iina")

      webView = WKWebView(frame: .zero, configuration: config)
      if #available(macOS 13.3, *) {
        webView.isInspectable = true
      }
      webView.navigationDelegate = self
      webView.uiDelegate = self
      webView.translatesAutoresizingMaskIntoConstraints = false
      webView.setValue(false, forKey: "drawsBackground")
      contentView?.addSubview(webView)
      Utility.quickConstraints(["H:|-0-[v]-0-|", "V:|-0-[v]-0-|"], ["v": webView])
    }
  }

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

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if let url = navigationAction.request.url, pluginInstance.canAccess(url: url) {
      decisionHandler(.cancel)
    } else {
      decisionHandler(.allow)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard isEnteringSimpleMode else { return }
    isEnteringSimpleMode = false
    
    if let style = pendingStyle {
      _simpleModeSetStyle(style)
    }
    if let content = pendingContent {
      _simpleModeSetContent(content)
    }
  }

  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
    let alert = NSAlert()
    alert.informativeText = message
    alert.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    await withCheckedContinuation { continuation in
      alert.beginSheetModal(for: self, completionHandler: { _ in
        continuation.resume()
      })
    }
  }

  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
    let alert = NSAlert()
    alert.informativeText = message
    alert.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    alert.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    return await withCheckedContinuation { continuation in
      alert.beginSheetModal(for: self) { res in
        continuation.resume(returning: res == .alertFirstButtonReturn)
      }
    }
  }

  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
    let alert = NSAlert()
    alert.informativeText = prompt

    // accessory view
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 16))
    input.translatesAutoresizingMaskIntoConstraints = false
    input.lineBreakMode = .byClipping
    input.usesSingleLineMode = true
    input.cell?.isScrollable = true
    if let inputValue = defaultText {
      input.stringValue = inputValue
    }
    let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 240, height: 20))
    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.addArrangedSubview(input)
    stackView.translatesAutoresizingMaskIntoConstraints = true
    alert.accessoryView = stackView

    // buttons
    alert.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    alert.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    alert.window.initialFirstResponder = input

    return await withCheckedContinuation { continuation in
      alert.beginSheetModal(for: self) { response in
        continuation.resume(returning: response == .alertFirstButtonReturn ? input.stringValue: nil)
      }
    }
  }

  private func _simpleModeSetStyle(_ style: String) {
    Utility.executeOnMainThread {
      webView.evaluateJavaScript("window.iina._simpleModeSetStyle(`\(style)`)") { (_, error) in
        if let error = error {
          Logger.log(error.localizedDescription, level: .error, subsystem: self.pluginInstance.subsystem)
        }
      }
    }
  }

  private func _simpleModeSetContent(_ content: String) {
    Utility.executeOnMainThread {
      webView.evaluateJavaScript("window.iina._simpleModeSetContent(`\(content)`)") { (_, error) in
        if let error = error {
          Logger.log(error.localizedDescription, level: .error, subsystem: self.pluginInstance.subsystem)
        }
      }
    }
  }
}

