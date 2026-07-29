//
//  PrefPluginPermissionListView.swift
//  iina
//
//  Created by Collider LI on 14/3/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

class PrefPluginPermissionListView: NSStackView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    self.orientation = .vertical
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  func setPlugin(_ plugin: JavascriptPlugin, onlyShowAddedFrom previousPlugin: JavascriptPlugin? = nil) {
    views.forEach { removeView($0) }

    let permissions: Set<JavascriptPlugin.Permission>
    if let previous = previousPlugin {
      permissions = plugin.permissions.subtracting(previous.permissions)
    } else {
      permissions = plugin.permissions
    }

    let localized = plugin.localizedPermissions(permissions)

    for p in localized {
      let vc = PrefPluginPermissionView(name: p.name, desc: p.desc, isDangerous: p.isDangerous)
      addView(vc.view, in: .top)
      Utility.quickConstraints(["H:|-0-[v]-0-|"], ["v": vc.view])
    }
  }
}
