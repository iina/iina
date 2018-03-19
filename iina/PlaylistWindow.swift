//
//  PlaylistWindow.swift
//  iina
//
//  Created by sidneys on 14.03.18.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PlaylistWindow: NSWindow {
  
  weak private var player: PlayerCore!

  var wrapperView: NSVisualEffectView?

  init(player: PlayerCore, view: NSView) {
    // retain player reference
    self.player = player

    // MARK: Position & Size
    // get playlist views' container window
    let window = self.player.mainWindow.window

    // get views' relative coordinates and derive its absolute coordinates
    let relativeRectangle = window?.convertFromScreen(view.frame)

    // calculate target coordinates on top of old window
    let x = ((relativeRectangle?.origin.x)! * -1) + (window?.frame.size.width)! - view.frame.size.width
    let y = (relativeRectangle?.origin.y)! * -1
    let width = view.bounds.width
    let height = view.bounds.height

    // generate target coordinates
    let targetRectangle = NSRect(x: x, y:y, width: width, height: height)

    // MARK: Super
    super.init(contentRect:targetRectangle, styleMask: [.fullSizeContentView, .titled, .resizable], backing: .buffered, defer: false)

    // MARK: Appearance
    self.styleMask = [.fullSizeContentView, .titled, .resizable]
    self.initialFirstResponder = nil
    self.level = (window?.level)!
    self.isMovableByWindowBackground = true
    self.appearance = window?.appearance
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .visible
    self.title = "Playlist"
    self.isOpaque = true
    self.makeKeyAndOrderFront(nil)

    // MARK: Setup Content View
    // create wrapper view
    wrapperView = NSVisualEffectView(frame: targetRectangle)
    wrapperView?.material = player.mainWindow.sideBarView.material
    wrapperView?.appearance = player.mainWindow.sideBarView.appearance
    wrapperView?.blendingMode = .behindWindow
    wrapperView?.state = .active
    self.contentView = wrapperView

    // MARK: Notifications
    // close playlist window when mainWindow closes
    NotificationCenter.default.addObserver(forName: .iinaMainWindowClosed, object: player, queue: .main) { _ in
      self.orderOut(self)
    }
  }
}
