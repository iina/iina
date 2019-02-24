//
//  PluginOverlayView.swift
//  iina
//
//  Created by Collider LI on 21/1/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Cocoa
import WebKit

class PluginOverlayView: WKWebView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    return nil
  }
}
