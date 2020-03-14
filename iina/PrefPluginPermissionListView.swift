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

  func setPlugin(_ plugin: JavascriptPlugin) {
    views.forEach { removeView($0) }

    let sorted = plugin.permissions.sorted { (a, b) in
      let da = a.isDangerous, db = b.isDangerous
      if da == db { return a.rawValue < b.rawValue }
      return da
    }

    for permission in sorted {
      func localize(_ key: String) -> String {
        return NSLocalizedString("permissions.\(permission.rawValue).\(key)", comment: "")
      }
      var desc = localize("desc")
      if case .networkRequest = permission {
        if plugin.domainList.contains("*") {
          desc += "\n- \(localize("any_site"))"
        } else {
          desc += "\n- "
          desc += plugin.domainList.joined(separator: "\n- ")
        }
      }
      let vc = PrefPluginPermissionView(name: localize("name"), desc: desc, isDangerous: permission.isDangerous)
      addView(vc.view, in: .top)
      Utility.quickConstraints(["H:|-0-[v]-0-|"], ["v": vc.view])
    }
  }
}
