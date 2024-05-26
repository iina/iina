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
  func items() -> [JavascriptPluginMenuItem]
  func removeAt(_ index: Int) -> Bool
  func removeAllItems()
  func forceUpdate()
}

class JavascriptAPIMenu: JavascriptAPI, JavascriptAPIMenuExportable {
  func item(_ title: String, _ action: JSValue,  _ options: JSValue) -> JavascriptPluginMenuItem {
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

  func separator() -> JavascriptPluginMenuItem {
    let item = JavascriptPluginMenuItem(title: "", selected: false, enabled: false)
    item.isSeparator = true
    return item
  }

  func addItem(_ item: JavascriptPluginMenuItem) {
    self.pluginInstance.menuItems.append(item)
  }

  func items() -> [JavascriptPluginMenuItem] {
    return self.pluginInstance.menuItems
  }

  func removeAt(_ index: Int) -> Bool {
    guard let item = self.pluginInstance.menuItems[at: index] else {
      return false
    }
    if let action = item.action {
      JSContext.current()!.virtualMachine.removeManagedReference(action, withOwner: self)
    }
    self.pluginInstance.menuItems.remove(at: index)
    return true
  }

  func removeAllItems() {
    for item in self.pluginInstance.menuItems {
      item.forAllSubItems {
        if let action = $0.action {
          JSContext.current()!.virtualMachine.removeManagedReference(action, withOwner: self)
        }
      }
    }
    self.pluginInstance.menuItems.removeAll()
  }

  func forceUpdate() {
    Utility.executeOnMainThread {
      AppDelegate.shared.menuController?.updatePluginMenu()
    }
  }
}

fileprivate func getKeyedValue(_ object: JSValue, _ key: String) -> JSValue? {
  guard object.isObject else { return nil }
  guard let value = object.objectForKeyedSubscript(key), !value.isUndefined else {
    return nil
  }
  return value
}
