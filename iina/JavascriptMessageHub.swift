//
//  JavascriptMessageHub.swift
//  iina
//
//  Created by Collider LI on 22/10/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation
import WebKit


class JavascriptMessageHub {
  weak var reference: JavascriptAPI!
  private var listeners: [String: JSManagedValue] = [:]

  init(reference: JavascriptAPI) {
    self.reference = reference
  }

  func postMessage(to webView: WKWebView, name: String, data: JSValue) {
    DispatchQueue.main.async {
      guard let object = data.toObject(),
         let data = try? JSONSerialization.data(withJSONObject: object),
         let dataString = String(data: data, encoding: .utf8) else {
          webView.evaluateJavaScript("window.iina._emit(`\(name)`)")
          return
      }
      webView.evaluateJavaScript("window.iina._emit(`\(name)`, `\(dataString)`)")
    }
  }

  func addListener(forEvent name: String, callback: JSValue) {
    if let previousCallback = listeners[name] {
      JSContext.current()!.virtualMachine.removeManagedReference(previousCallback, withOwner: reference)
    }
    let managed = JSManagedValue(value: callback)
    listeners[name] = managed
    JSContext.current()!.virtualMachine.addManagedReference(managed, withOwner: reference)
  }

  func callListener(forEvent name: String, withDataString dataString: String?) {
    guard let callback = listeners[name] else { return }

    guard let dataString = dataString,
      let data = dataString.data(using: .utf8),
      let decoded = try? JSONSerialization.jsonObject(with: data) else {
      callback.value.call(withArguments: [])
      return
    }

    callback.value.call(withArguments: [JSValue(object: decoded, in: callback.value.context) ?? NSNull()])
  }

  func callListener(forEvent name: String, withDataObject dataObject: Any?) {
    guard let callback = listeners[name] else { return }
    callback.value.call(withArguments: [JSValue(object: dataObject, in: callback.value.context) ?? NSNull()])
  }

  func receiveMessageFromUserContentController(_ message: WKScriptMessage) {
    guard let dict = message.body as? [Any], dict.count == 2,
      let name = dict[0] as? String
      else { return }

    callListener(forEvent: name, withDataString: dict[1] as? String)
  }

  static let bridgeScript = """
window.iina = {
  listeners: {},
  _emit(name, data) {
    const callback = this.listeners[name];
    if (typeof callback === "function") {
      callback.call(null, data ? JSON.parse(data) : undefined);
    }
  },
  _simpleModeSetStyle(string) {
    document.getElementById("style").innerHTML = string;
  },
  _simpleModeSetContent(string) {
    document.getElementById("content").innerHTML = string;
  },
  onMessage(name, callback) {
    this.listeners[name] = callback;
  },
  postMessage(name, data) {
    webkit.messageHandlers.iina.postMessage([name, JSON.stringify(data)]);
  },
};
"""
}
