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
  func item(_ title: String, _ action: JSValue, _ options: JSValue) -> JavascriptPluginMenuItem
  func separator() -> JavascriptPluginMenuItem
  func addItem(_ item: JavascriptPluginMenuItem)
  func removeAllItems()
}

class JavascriptAPIMenu: JavascriptAPI, JavascriptAPIMenuExportable {
  @objc func item(_ title: String, _ action: JSValue,  _ options: JSValue) -> JavascriptPluginMenuItem {
    let action_ = action.isNull ? nil : action
    let enabled = getKeyedValue(options, "enabled")?.toBool() ?? true
    let selected = getKeyedValue(options, "selected")?.toBool() ?? false
    let key: String? = getKeyedValue(options, "keyBinding")?.toString()
    let item = JavascriptPluginMenuItem(title: title,
                                        action: action_,
                                        selected: selected,
                                        enabled: enabled,
                                        key: key,
                                        owner: self)
    return item
  }

  @objc func separator() -> JavascriptPluginMenuItem {
    let item = JavascriptPluginMenuItem(title: "", selected: false, enabled: false)
    item.isSeparator = true
    return item
  }

  @objc func addItem(_ item: JavascriptPluginMenuItem) {
    self.pluginInstance.menuItems.append(item)
  }

  @objc func removeAllItems() {
    for item in self.pluginInstance.menuItems {
      item.forAllSubItems {
        if let action = $0.action {
          JSContext.current()!.virtualMachine.removeManagedReference(action, withOwner: self)
        }
      }
    }
    self.pluginInstance.menuItems.removeAll()
  }
}

fileprivate func getKeyedValue(_ object: JSValue, _ key: String) -> JSValue? {
  guard object.isObject else { return nil }
  guard let value = object.objectForKeyedSubscript(key), !value.isUndefined else {
    return nil
  }
  return value
}
