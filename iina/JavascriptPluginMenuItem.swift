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
  var items: [JavascriptPluginMenuItem] { get }
  var title: String { get set }
  var selected: Bool { get set }
  var enabled: Bool { get set }
  var keyBinding: String? { get set }

  func addSubMenuItem(_ item: JavascriptPluginMenuItem) -> Self
}

class JavascriptPluginMenuItem: NSObject, JavascriptPluginMenuItemExportable {
  unowned var nsMenuItem: NSMenuItem?

  var items: [JavascriptPluginMenuItem] = []
  var title: String {
    didSet {
      guard let item = nsMenuItem else { return }
      item.title = title
    }
  }
  var action: JSManagedValue?
  var selected: Bool {
    didSet {
      guard let item = nsMenuItem else { return }
      item.state = selected ? .on : .off
    }
  }
  var enabled: Bool {
    didSet {
      guard let item = nsMenuItem else { return }
      item.isEnabled = enabled
    }
  }
  var keyBinding: String? {
    didSet {
      guard let item = nsMenuItem else { return }
      if let key = keyBinding,let (kEqv, kMdf) = KeyCodeHelper.macOSKeyEquivalent(from: key) {
        item.keyEquivalent = kEqv
        item.keyEquivalentModifierMask = kMdf
      }
    }
  }
  var isSeparator: Bool

  init(title: String, selected: Bool, enabled: Bool, keyBinding: String? = nil) {
    self.title = title
    self.selected = selected
    self.enabled = enabled
    self.keyBinding = keyBinding
    self.isSeparator = false
  }

  convenience init(title: String, action: JSValue?, selected: Bool, enabled: Bool, key: String?, owner: JavascriptAPIMenu) {
    self.init(title: title, selected: selected, enabled: enabled, keyBinding: key)
    if let action = action {
      self.action = JSManagedValue(value: action)
      JSContext.current()!.virtualMachine.addManagedReference(self.action, withOwner: owner)
    }
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
