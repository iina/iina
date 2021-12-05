//
//  CameraAreaMaskWindow.swift
//  iina
//
//  Created by low-batt on 12/4/21.
//  Copyright © 2021 lhc. All rights reserved.
//

import Cocoa

/// A window that is used to hide the top of the screen on Macs whose screen includes a camera housing.
///
/// When taking a window into fullscreen mode the method `NSWindow.toggleFullScreen` will automatically black out the
/// portions of the screen to the left and right of the camera housing on Macs with a camera that intrude into the screen. IINA normally
/// uses this method to go into fullscreen mode.
///
/// For the legacy full screen feature IINA implements custom full screen behavior. This puts the burden on IINA to properly handle Macs
/// containing a camera housing within the screen. On such Macs IINA's window displaying the video will avoid using the top portion of
/// the screen containing the camera. But this means the screen's wallpaper will be visible to the left and right of the camera. This
/// window takes up the full screen and is displayed behind the video window in order to black out the portion of the screen to the
/// left and right of the camera housing.
class CameraAreaMaskWindow: NSWindow {

  override var canBecomeKey: Bool { false }

  override var canBecomeMain: Bool { false }

  override var isMiniaturizable: Bool { false }

  override var isResizable: Bool { false }

  override var isZoomable: Bool { false }

  convenience init(_ screen: NSScreen) {
    self.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false,
              screen: screen)
    animationBehavior = .none
    backgroundColor = NSColor.black
    hasShadow = false
    isExcludedFromWindowsMenu = true
    isMovable = false
    isOpaque = true
    isReleasedWhenClosed = false
    orderFront(nil)
  }
}
