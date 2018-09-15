//
//  PrefPluginViewController.swift
//  iina
//
//  Created by Collider LI on 12/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

fileprivate let cellViewIndentifier = NSUserInterfaceItemIdentifier("PluginCell")

class PrefPluginViewController: NSViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefPluginViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.plugins", comment: "Plug-ins")
  }

  var preferenceContentIsScrollable: Bool {
    return false
  }

  var plugins: [JavascriptPlugin] = []

  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var pluginInfoContentView: NSView!
  @IBOutlet weak var pluginNameLabel: NSTextField!
  @IBOutlet weak var pluginVersoinLabel: NSTextField!
  @IBOutlet weak var pluginDescLabel: NSTextField!
  @IBOutlet weak var pluginPermissionsView: NSStackView!

  override func viewDidLoad() {
    super.viewDidLoad()

    plugins = JavascriptPlugin.plugins
    tableView.delegate = self
    tableView.dataSource = self

    clearPluginPage()
  }

  private func clearPluginPage() {
    pluginInfoContentView.isHidden = true
  }

  private func loadPluginPage(_ plugin: JavascriptPlugin) {
    pluginInfoContentView.isHidden = false
    pluginNameLabel.stringValue = plugin.name
    pluginVersoinLabel.stringValue = plugin.version
    pluginDescLabel.stringValue = plugin.description ?? "No Description"

    pluginPermissionsView.views.forEach { pluginPermissionsView.removeView($0) }

    for permission in plugin.permissions {
      func l10n(_ key: String) -> String {
        return NSLocalizedString("permissions.\(permission.rawValue).\(key)", comment: "")
      }
      var desc = l10n("desc")
      if case .networkRequest = permission {
        if plugin.domainList.contains("*") {
          desc += "\n   - \(l10n("any_site"))"
        } else {
          desc += "\n   - "
          desc += plugin.domainList.joined(separator: "\n   - ")
        }
      }
      let vc = PrefPluginPermissionView(name: l10n("name"), desc: desc, isDangerous: permission.isDangerous)
      pluginPermissionsView.addView(vc.view, in: .top)
      Utility.quickConstraints(["H:|-0-[v]-0-|"], ["v": vc.view])
    }
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
