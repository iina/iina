//
//  JavascriptPluginMenuItem.swift
//  iina
//
//  Created by Collider LI on 10/12/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa
import JavaScriptCore

@objc protocol JavascriptPluginMenuItemExportable: JSExport {
  var items: [JavascriptPluginMenuItem] { get set }
  var title: String { get set }
  var selected: Bool { get set }
  var enabled: Bool { get set }

  func addSubMenuItem(_ item: JavascriptPluginMenuItem) -> Self
}

class JavascriptPluginMenuItem: NSObject, JavascriptPluginMenuItemExportable {
  var items: [JavascriptPluginMenuItem] = []
  var title: String
  var action: JSManagedValue?
  var selected: Bool
  var enabled: Bool
  var isSeparator: Bool

  init(title: String, selected: Bool, enabled: Bool) {
    self.title = title
    self.selected = selected
    self.enabled = enabled
    self.isSeparator = false
  }

  convenience init(title: String, action: JSValue, selected: Bool, enabled: Bool) {
    self.init(title: title, selected: selected, enabled: enabled)
    self.action = JSManagedValue(value: action)
    JSContext.current()?.virtualMachine.addManagedReference(action, withOwner: self)
  }

  func addSubMenuItem(_ item: JavascriptPluginMenuItem) -> Self {
    self.items.append(item)
    return self
  }

  /// Return false to indicate that the call failed.
  func callAction() -> Bool {
    if let action = action, let value = action.value {
      // if the value is null or undefined, the item has an empty action.
      if value.isNull || value.isUndefined { return true }
      return value.call(withArguments: [self]) != nil
    }
    return false
  }
}
