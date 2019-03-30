//
//  PrefPluginViewController.swift
//  iina
//
//  Created by Collider LI on 12/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa
import WebKit

fileprivate let cellViewIndentifier = NSUserInterfaceItemIdentifier("PluginCell")

class PrefPluginViewController: NSViewController, PreferenceWindowEmbeddable {
  override var nibName: NSNib.Name {
    return NSNib.Name("PrefPluginViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.plugins", comment: "Plug-ins")
  }

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_general"))!
  }

  var preferenceContentIsScrollable: Bool {
    return false
  }

  var plugins: [JavascriptPlugin] = []
  var currentPlugin: JavascriptPlugin?

  @IBOutlet weak var tabView: NSTabView!
  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var pluginInfoContentView: NSView!
  @IBOutlet weak var pluginNameLabel: NSTextField!
  @IBOutlet weak var pluginVersionLabel: NSTextField!
  @IBOutlet weak var pluginAuthorLabel: NSTextField!
  @IBOutlet weak var pluginDescLabel: NSTextField!
  @IBOutlet weak var pluginPermissionsView: NSStackView!
  @IBOutlet weak var pluginWebsiteEmailStackView: NSStackView!
  @IBOutlet weak var pluginWebsiteBtn: NSButton!
  @IBOutlet weak var pluginEmailBtn: NSButton!
  @IBOutlet weak var pluginSupportStackView: NSStackView!
  @IBOutlet weak var pluginBinaryHelpTextView: NSView!
  @IBOutlet weak var pluginPreferencesContentView: NSView!
  var pluginPreferencesWebView: WKWebView!
  var pluginPreferencesWebViewHeight: NSLayoutConstraint!
  var pluginPreferencesViewController: PrefPluginPreferencesViewController!

  override func viewDidLoad() {
    super.viewDidLoad()

    plugins = JavascriptPlugin.plugins
    tableView.delegate = self
    tableView.dataSource = self

    clearPluginPage()
  }

  private func createPreferenceView() {
    let config = WKWebViewConfiguration()
    config.userContentController.addUserScript(WKUserScript(source: """
      let counter = 0;
      window.onerror = (msg, url, line, col, error) => {
        window.iina._post("error", [msg, url, line, col, error]);
      };
      window.iina = {
        log(message) {
          this._post("log", [message])
        },
        _post(name, data) {
          webkit.messageHandlers.iina.postMessage([name, data]);
        },
        _callbacks: {},
        _call(id, data) {
          this._callbacks[id].call(null, data);
          delete this._callbacks[id];
        }
      };
      window.iina.preferences = {
        set(name, value) {
          window.iina._post("set", [name, value]);
        },
        get(name, callback) {
          counter++;
          window.iina._post("get", [name, counter]);
          if (typeof callback !== "function")
            throw Error("Callback is not provided.");
          window.iina._callbacks[counter] = callback;
        },
      };
    """, injectionTime: .atDocumentStart, forMainFrameOnly: true))

    config.userContentController.addUserScript(WKUserScript(source: """
      const { preferences } = window.iina;
      const inputs = document.querySelectorAll("input[data-pref-key]");
      Array.prototype.forEach.call(inputs, input => {
          const key = input.dataset.prefKey;
          iina.log(key)
          preferences.get(key, (value) => {
              iina.log(value)
              input.value = value;
          });
          input.addEventListener("change", () => {
              let value = input.value;
              switch (input.dataset.type) {
                  case "int": value = parseInt(value); break;
                  case "float": value = parseFloat(value); break;
              }
              preferences.set(key, value);
          });
      });
    """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

    config.userContentController.add(self, name: "iina")
    
    pluginPreferencesWebView = WKWebView(frame: .zero, configuration: config)
    pluginPreferencesViewController = PrefPluginPreferencesViewController()
    pluginPreferencesViewController.view = pluginPreferencesWebView

    pluginPreferencesWebView.navigationDelegate = self
    pluginPreferencesWebView.translatesAutoresizingMaskIntoConstraints = false
    pluginPreferencesContentView.addSubview(pluginPreferencesWebView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": pluginPreferencesWebView])
    pluginPreferencesWebViewHeight = NSLayoutConstraint(item: pluginPreferencesWebView!, attribute: .height,
                                                        relatedBy: .equal, toItem: nil, attribute: .notAnAttribute,
                                                        multiplier: 1, constant: 0)
    pluginPreferencesWebView.addConstraint(pluginPreferencesWebViewHeight)
  }

  @IBAction func tabSwitched(_ sender: NSSegmentedControl) {
    tabView.selectTabViewItem(at: sender.selectedSegment)
    if sender.selectedSegment == 2, let currentPlugin = currentPlugin, let prefURL = currentPlugin.preferencesPageURL {
      if pluginPreferencesWebView == nil {
        createPreferenceView()
      }
      pluginPreferencesWebView.loadFileURL(prefURL, allowingReadAccessTo: currentPlugin.root)
      pluginPreferencesViewController.plugin = currentPlugin
    }
  }

  @IBAction func websiteBtnAction(_ sender: NSButton) {
    if let website = currentPlugin?.authorURL, let url = URL(string: website) {
      NSWorkspace.shared.open(url)
    }
  }

  @IBAction func emailBtnAction(_ sender: NSButton) {
    if let email = currentPlugin?.authorEmail, let url = URL(string: "mailto:\(email)") {
      NSWorkspace.shared.open(url)
    }
  }

  @IBAction func openBinaryDirBtnAction(_ sender: Any) {
    NSWorkspace.shared.open(Utility.binariesURL)
  }

  private func clearPluginPage() {
    pluginInfoContentView.isHidden = true
  }

  private func loadPluginPage(_ plugin: JavascriptPlugin) {
    pluginInfoContentView.isHidden = false
    pluginNameLabel.stringValue = plugin.name
    pluginAuthorLabel.stringValue = plugin.authorName
    pluginVersionLabel.stringValue = plugin.version
    pluginDescLabel.stringValue = plugin.description ?? "No Description"
    pluginWebsiteEmailStackView.setVisibilityPriority(plugin.authorEmail == nil ? .notVisible : .mustHold, for: pluginEmailBtn)
    pluginWebsiteEmailStackView.setVisibilityPriority(plugin.authorURL == nil ? .notVisible : .mustHold, for: pluginWebsiteBtn)
    pluginSupportStackView.setVisibilityPriority(.notVisible, for: pluginBinaryHelpTextView)

    pluginPermissionsView.views.forEach { pluginPermissionsView.removeView($0) }

    for permission in plugin.permissions {
      func l10n(_ key: String) -> String {
        return NSLocalizedString("permissions.\(permission.rawValue).\(key)", comment: "")
      }
      var desc = l10n("desc")
      if case .networkRequest = permission {
        if plugin.domainList.contains("*") {
          desc += "\n- \(l10n("any_site"))"
        } else {
          desc += "\n- "
          desc += plugin.domainList.joined(separator: "\n- ")
        }
      } else if case .callProcess = permission {
        pluginSupportStackView.setVisibilityPriority(.mustHold, for: pluginBinaryHelpTextView)
      }
      let vc = PrefPluginPermissionView(name: l10n("name"), desc: desc, isDangerous: permission.isDangerous)
      pluginPermissionsView.addView(vc.view, in: .top)
      Utility.quickConstraints(["H:|-0-[v]-0-|"], ["v": vc.view])
    }

    currentPlugin = plugin
  }

}

extension PrefPluginViewController: NSTableViewDelegate, NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return plugins.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return plugins[at: row]
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard
      let view = tableView.makeView(withIdentifier: cellViewIndentifier, owner: self) as? NSTableCellView,
      let plugin = plugins[at: row]
      else { return nil }
    view.textField?.stringValue = plugin.name
    return view
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard let plugin = plugins[at: tableView.selectedRow] else {
      clearPluginPage()
      return
    }
    loadPluginPage(plugin)
  }
}

extension PrefPluginViewController: WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    self.pluginPreferencesWebView.evaluateJavaScript("document.readyState", completionHandler: { (complete, error) in
      if complete != nil {
        self.pluginPreferencesWebView.evaluateJavaScript("document.body.scrollHeight", completionHandler: { (height, error) in
          self.pluginPreferencesWebViewHeight.constant = height as! CGFloat
        })
      }
    })
  }
}

extension PrefPluginViewController: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let plugin = currentPlugin else { return }
    guard let dict = message.body as? [Any], dict.count == 2 else { return }
    guard let name = dict[0] as? String else { return }
    guard let data = dict[1] as? [Any], let prefName = data[0] as? String else { return }
    if name == "set" {
      plugin.preferences[prefName] = data[1]
    } else if name == "get" {
      let value = plugin.preferences[prefName]
      let result: String
      if let value = value {
        if JSONSerialization.isValidJSONObject(value), let json = try? String(data: JSONSerialization.data(withJSONObject: value, options: []), encoding: .utf8) {
          result = json
        } else if value is String {
          result = "\"\(value)\""
        } else {
          result = "\(value)"
        }
      } else {
        result = "null"
      }
      pluginPreferencesWebView.evaluateJavaScript("window.iina._call(\(data[1]), \(result))")
    } else if name == "error" {
      Logger.log("JS:\(plugin.name) Preference page \(data[0]) \(data[2]),\(data[3]): \(data[4])")
    } else if name == "log" {
      Logger.log("JS:\(plugin.name) Preference page: \(data[0])")
    }
  }
}

class PrefPluginPreferencesViewController: NSViewController {
  var plugin: JavascriptPlugin?

  override func viewWillDisappear() {
    if let plugin = plugin {
      plugin.syncPreferences()
    }
  }
}
