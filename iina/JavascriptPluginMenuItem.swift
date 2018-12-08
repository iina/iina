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

  func addSubMenuItem(_ item: JavascriptPluginMenuItem)
}

class JavascriptPluginMenuItem: NSObject, JavascriptPluginMenuItemExportable {
  var items: [JavascriptPluginMenuItem] = []
  var title: String
  var action: JSValue

  init(title: String, action: JSValue) {
    self.title = title
    self.action = action
  }

  func addSubMenuItem(_ item: JavascriptPluginMenuItem) {
    self.items.append(item)
  }
}
