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
  func item(_ title: String, _ action: JSValue) -> JavascriptPluginMenuItem
  func addItem(_ item: JavascriptPluginMenuItem)
  func removeAllItems()
}

class JavascriptAPIMenu: JavascriptAPI, JavascriptAPIMenuExportable {
  @objc func item(_ title: String, _ action: JSValue) -> JavascriptPluginMenuItem {
    return JavascriptPluginMenuItem(title: title, action: action)
  }

  @objc func addItem(_ item: JavascriptPluginMenuItem) {
    guard permitted(to: .addMenuItems) else { return }
    self.pluginInstance.menuItems.append(item)
  }

  @objc func removeAllItems() {
    self.pluginInstance.menuItems.removeAll()
  }
}
