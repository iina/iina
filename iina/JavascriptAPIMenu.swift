//
//  JavascriptAPIMenu.swift
//  iina
//
//  Created by Collider LI on 9/12/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIMenuExportable: JSExport {
  func item(_ title: String, _ action: JSValue, _ selected: Bool, _ enabled: Bool) -> JavascriptPluginMenuItem
  func separator() -> JavascriptPluginMenuItem
  func addItem(_ item: JavascriptPluginMenuItem)
  func removeAllItems()
}

class JavascriptAPIMenu: JavascriptAPI, JavascriptAPIMenuExportable {
  @objc func item(_ title: String, _ action: JSValue, _ selected: Bool = false, _ enabled: Bool = true) -> JavascriptPluginMenuItem {
    let item = JavascriptPluginMenuItem(title: title, action: action, selected: selected, enabled: enabled)
    return item
  }

  @objc func separator() -> JavascriptPluginMenuItem {
    let item = JavascriptPluginMenuItem(title: "", selected: false, enabled: false)
    item.isSeparator = true
    return item
  }

  @objc func addItem(_ item: JavascriptPluginMenuItem) {
    guard permitted(to: .addMenuItems) else { return }
    self.pluginInstance.menuItems.append(item)
  }

  @objc func removeAllItems() {
    self.pluginInstance.menuItems.removeAll()
  }
}
