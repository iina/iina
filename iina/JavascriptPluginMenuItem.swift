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
  var action: JSValue { get set }
  var selected: Bool { get set }
  var enabled: Bool { get set }

  func addSubMenuItem(_ item: JavascriptPluginMenuItem)
}

class JavascriptPluginMenuItem: NSObject, JavascriptPluginMenuItemExportable {
  var items: [JavascriptPluginMenuItem] = []
  var title: String
  var action: JSValue
  var selected: Bool
  var enabled: Bool

  init(title: String, action: JSValue, selected: Bool, enabled: Bool) {
    self.title = title
    self.action = action
    self.selected = selected
    self.enabled = enabled
  }

  func addSubMenuItem(_ item: JavascriptPluginMenuItem) {
    self.items.append(item)
  }
}
