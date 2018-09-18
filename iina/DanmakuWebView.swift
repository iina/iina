//
//  DanmakuWebView.swift
//  iina
//
//  Created by xjbeta on 2018/9/17.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa
import WebKit

class DanmakuWebView: WKWebView {
  
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
      // Drawing code here.
  }
  
  override func hitTest(_ point: NSPoint) -> NSView? {
    return nil
  }
}
