//
//  PlaylistWindow.swift
//  iina
//
//  Created by Sidney Bofah on 14.03.18.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PlaylistWindow: NSWindow {

  static let tag = arc4random() % 10

  init(contentRect: NSRect) {
    //let window = NSWindow(contentRect:rect, styleMask: [.fullSizeContentView, .titled, .resizable], backing: .buffered, defer: false)
    super.init(contentRect:contentRect, styleMask: [.fullSizeContentView, .titled, .resizable], backing: .buffered, defer: false)
    
    self.styleMask = [.fullSizeContentView, .titled, .resizable]
    self.initialFirstResponder = nil
    self.isMovableByWindowBackground = true
    self.appearance = NSAppearance(named: .vibrantDark)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .visible
    self.title = "Playlist"
    self.isOpaque = true
    self.makeKeyAndOrderFront(nil)
    
  }

}
