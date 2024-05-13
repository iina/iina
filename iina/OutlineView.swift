//
//  OutlineView.swift
//  iina
//
//  Created by low-batt on 4/6/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

/// A custom [NSOutlineView](https://developer.apple.com/documentation/appkit/nsoutlineview).
///
/// If the IINA `Enable animations` setting is disabled then when the
/// [Disclosure triangles](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls#Disclosure-triangles)
/// in the outline view are used to expand or collapse a row the sliding animation will be suppressed.
class OutlineView: NSOutlineView {

  override func collapseItem(_ item: Any?, collapseChildren: Bool) {
    guard !Preference.bool(for: PK.enableAnimations) else {
      super.collapseItem(item, collapseChildren: collapseChildren)
      return
    }
    NSAnimationContext.beginGrouping()
    defer { NSAnimationContext.endGrouping() }
    NSAnimationContext.current.duration = 0.0
    super.collapseItem(item, collapseChildren: collapseChildren)
  }

  override func expandItem(_ item: Any?, expandChildren: Bool) {
    guard !Preference.bool(for: PK.enableAnimations) else {
      super.expandItem(item, expandChildren: expandChildren)
      return
    }
    NSAnimationContext.beginGrouping()
    defer { NSAnimationContext.endGrouping() }
    NSAnimationContext.current.duration = 0.0
    super.expandItem(item, expandChildren: expandChildren)
  }
}
