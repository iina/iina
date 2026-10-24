//
//  PluginSidebarView.swift
//  iina
//
//  Created by Collider LI on 11/10/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa
@preconcurrency import WebKit

class PluginSidebarView: WKWebView, WKNavigationDelegate {
  weak private var pluginInstance: JavascriptPluginInstance!
  private var backgroundClickHandler: BackgroundClickHandler?
  private var appearanceBridge: PluginAppearanceBridge?

  private final class BackgroundClickHandler: NSObject, WKScriptMessageHandler {
    weak var webView: PluginSidebarView?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
      guard message.frameInfo.isMainFrame, let webView, message.webView === webView,
            let point = message.body as? [Double], point.count == 3, point[2] == 0,
            point.allSatisfy({ $0.isFinite }),
            let windowController = webView.window?.windowController as? MainWindowController else { return }
      let local = NSPoint(x: webView.bounds.minX + point[0],
                          y: webView.isFlipped ? webView.bounds.minY + point[1] : webView.bounds.maxY - point[1])
      guard webView.bounds.contains(local) else { return }
      windowController.sidebars.activatePluginBackground(webView, at: webView.convert(local, to: nil), button: Int(point[2]))
    }
  }

  // WKContentView cannot distinguish HTML controls from background; the DOM must report background clicks.
  static let backgroundClickScript = #"""
  (() => {
    let press = null;
    const controls = 'button,a[href],input,select,textarea,summary,label,canvas,iframe,video,audio,' +
      '[contenteditable]:not([contenteditable="false"]),[draggable="true"],[tabindex]:not([tabindex="-1"]),' +
      '[role="button"],[role="link"],[role="slider"],[role="checkbox"],[role="radio"],[role="switch"],' +
      '[role="textbox"],[role="combobox"],[role="listbox"],[role="option"],[role="menuitem"],' +
      '[role="tab"],[role="treeitem"],[role="spinbutton"],[role="scrollbar"]';
    function background(event) {
      return !event.composedPath().some(element => element instanceof Element &&
        (element.matches(controls) || element.hasAttribute('onclick') ||
         typeof element.onclick === 'function' || getComputedStyle(element).cursor === 'pointer'));
    }
    addEventListener('pointerdown', event => {
      press = event.button === 0 && !event.ctrlKey && background(event) ?
        { x: event.clientX, y: event.clientY, button: event.button } : null;
    }, true);
    addEventListener('pointermove', event => {
      if (press && Math.hypot(event.clientX - press.x, event.clientY - press.y) > 3) press = null;
    }, true);
    addEventListener('pointercancel', () => { press = null; }, true);
    addEventListener('wheel', () => { press = null; }, { capture: true, passive: true });
    addEventListener('click', event => {
      const start = press;
      press = null;
      if (!start || start.button !== 0 || event.button !== 0 || event.detail !== 1 || !background(event) ||
          Math.hypot(event.clientX - start.x, event.clientY - start.y) > 3) return;
      queueMicrotask(() => {
        if (!event.defaultPrevented && !getSelection()?.toString()) {
          webkit.messageHandlers.iinaPanelBackground.postMessage([event.clientX, event.clientY, 0]);
        }
      });
    }, true);
  })();
  """#

  deinit {
    appearanceBridge?.invalidate()
    configuration.userContentController.removeScriptMessageHandler(forName: "iina")
    configuration.userContentController.removeScriptMessageHandler(forName: "iinaPanelBackground", contentWorld: .defaultClient)
  }

  static func create(pluginInstance: JavascriptPluginInstance) -> PluginSidebarView {
    let config = WKWebViewConfiguration()
    config.userContentController.addUserScript(
      WKUserScript(source: JavascriptMessageHub.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )

    config.userContentController.add(pluginInstance.apis!["sidebar"] as! WKScriptMessageHandler, name: "iina")

    let webView = PluginSidebarView(frame: .zero, configuration: config)
    if #available(macOS 13.3, *) {
      webView.isInspectable = true
    }
    webView.pluginInstance = pluginInstance
    webView.appearanceBridge = PluginAppearanceBridge(webView: webView)
    let handler = BackgroundClickHandler()
    handler.webView = webView
    webView.backgroundClickHandler = handler
    config.userContentController.add(handler, contentWorld: .defaultClient, name: "iinaPanelBackground")
    config.userContentController.addUserScript(WKUserScript(source: backgroundClickScript,
      injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
    webView.navigationDelegate = webView
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.setValue(false, forKey: "drawsBackground")

    return webView
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    appearanceBridge?.prepareForNavigation()
    if let url = navigationAction.request.url, pluginInstance.canAccess(url: url) {
      decisionHandler(.cancel)
    } else {
      decisionHandler(.allow)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!){
    appearanceBridge?.didFinishNavigation()
    if let wc = window?.windowController as? PlayerWindowController {
      wc.player.events.emit(.pluginOverlayLoaded)
    }
  }
}
