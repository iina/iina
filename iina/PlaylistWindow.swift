//
//  PlaylistWindow.swift
//  iina
//
//  Created by sidneys on 14.03.18.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PlaylistWindow: NSWindow {

  init(playlistView: NSView) {
    // MARK: Position & Size
    // Get playlist views' container window (fallback to
    let window = playlistView.window ?? NSApplication.shared.mainWindow

    if playlistView.window == nil {
      Utility.log("Playlist views not fully loaded yet. Using fallback positioning.")
    }

    // Get views' relative coordinates
    let relativeRectangle = window?.convertFromScreen(playlistView.frame)

    // Calculate absolute coordinates for window
    let x = ((relativeRectangle?.origin.x)! * -1) + (window?.frame.size.width)! - playlistView.frame.size.width
    let y = (relativeRectangle?.origin.y)! * -1
    let width = playlistView.bounds.width
    let height = playlistView.bounds.height

    // Generate target coordinates
    let targetRectangle = NSRect(x: x, y:y, width: width, height: height)

    // MARK: Super
    super.init(contentRect:targetRectangle, styleMask: [.fullSizeContentView, .titled, .resizable], backing: .buffered, defer: false)

    // MARK: Appearance
    self.styleMask = [.fullSizeContentView, .titled, .resizable]
    self.initialFirstResponder = nil
    self.isMovableByWindowBackground = true
    self.appearance = NSAppearance(named: .vibrantDark)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .visible
    self.title = "Playlist"
    self.isOpaque = true
    self.makeKeyAndOrderFront(nil)

    // MARK: Content View (NSVisualEffectView Wrapper)
    let view = NSVisualEffectView(frame: targetRectangle)
    view.material = .dark
    view.blendingMode = .behindWindow
    view.state = .active
    self.contentView = view
  }
}
