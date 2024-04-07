//
//  OutlineView.swift
//  iina
//
//  Created by low-batt on 4/6/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

/// A [NSOutlineView](https://developer.apple.com/documentation/appkit/nsoutlineview) that adjusts animation
/// behavior based on the macOS [Reduce motion](https://support.apple.com/guide/mac-help/stop-or-reduce-onscreen-motion-mchlc03f57a1/mac)
/// setting.
///
/// If the macOS [System Settings](https://support.apple.com/en-gb/guide/mac-help/mh15217/mac) accessibility
/// option [Reduce motion](https://support.apple.com/en-gb/guide/mac-help/mchlc03f57a1/mac) is enabled then
/// when the [Disclosure triangles](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls#Disclosure-triangles) in the outline view are
/// used to expand or collapse a row the sliding animation will be changed to be instantaneous.
///
/// Proper handling of the Reduce motion preference setting is covered in the
/// [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/accessibility#Motion).
class OutlineView: NSOutlineView {

  override func collapseItem(_ item: Any?, collapseChildren: Bool) {
    guard AccessibilityPreferences.motionReductionEnabled else {
      super.collapseItem(item, collapseChildren: collapseChildren)
      return
    }
    NSAnimationContext.beginGrouping()
    defer { NSAnimationContext.endGrouping() }
    NSAnimationContext.current.duration = 0.0
    super.collapseItem(item, collapseChildren: collapseChildren)
  }

  override func expandItem(_ item: Any?, expandChildren: Bool) {
    guard AccessibilityPreferences.motionReductionEnabled else {
      super.expandItem(item, expandChildren: expandChildren)
      return
    }
    NSAnimationContext.beginGrouping()
    defer { NSAnimationContext.endGrouping() }
    NSAnimationContext.current.duration = 0.0
    super.expandItem(item, expandChildren: expandChildren)
  }
}
