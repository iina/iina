//
//  MainWindow.swift
//  iina
//
//  Created by Collider LI on 10/1/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class MainWindow: NSWindow {
  var forceKeyAndMain = false

  override func keyDown(with event: NSEvent) {
    if menu?.performKeyEquivalent(with: event) == true {
      return
    }
    /// Forward all key events which the window receives to its controller.
    /// This allows `ESC` & `TAB` key bindings to work, instead of getting swallowed by
    /// MacOS keyboard focus navigation (which we don't use).
    if let controller = windowController as? MainWindowController {
      controller.keyDown(with: event)
    } else {
      super.keyDown(with: event)
    }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    /// AppKit by default will prioritize menu item key equivalents over arrow key navigation
    /// (although for some reason it is the opposite for `ESC`, `TAB`, `ENTER` or `RETURN`).
    /// Need to add an explicit check here for arrow keys to ensure that they always work when desired.
    if let responder = firstResponder, shouldFavorArrowKeyNavigation(for: responder) {

      let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
      let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)

      switch normalizedKeyCode {
      case "UP", "DOWN", "LEFT", "RIGHT":
        // Send arrow keys to view to enable key navigation
        responder.keyDown(with: event)
        return true
      default:
        break
      }
    }
    return super.performKeyEquivalent(with: event)
  }

  private func shouldFavorArrowKeyNavigation(for responder: NSResponder) -> Bool {
    return responder as? NSTextView != nil
  }

  override var canBecomeKey: Bool {
    forceKeyAndMain ? true : super.canBecomeKey
  }
  
  override var canBecomeMain: Bool {
    forceKeyAndMain ? true : super.canBecomeMain
  }
}

class MainWindowContentView: NSView {
  override func resetCursorRects() {
    guard let controller = window?.windowController as? MainWindowController, controller.sideBarStatus == .playlist else { return }
    addCursorRect(controller.playlistDraggingRect, cursor: .resizeLeftRight)
  }

  /// Invoked automatically when the view’s geometry changes such that its tracking areas need to be recalculated.
  ///
  /// Previous to macOS Sequoia this method was not needed, AppKit properly handled the re-computation of the tracking area
  /// when the view geometry changed. But as of macOS 15 something is going wrong in AppKit and it fails to call `mouseMoved`
  /// after legacy full screen mode is entered or exited. See issues [#5535](https://github.com/iina/iina/issues/5535)
  /// and [#5288](https://github.com/iina/iina/issues/5288).
  /// - Note: This method intentionally does not check for the availability of macOS 15 as this method works fine with older versions
  ///     of macOS as well. This protects against Apple back porting the bad Sequoia behavior into older versions of macOS which
  ///     has occurred with past macOS problems.
  override func updateTrackingAreas() {
    defer { super.updateTrackingAreas() }
    guard trackingAreas.count == 1,
          let controller = window?.windowController as? MainWindowController else { return }
    controller.log("Recreating tracking area", level: .verbose)
    removeTrackingArea(trackingAreas[0])
    addTrackingArea(NSTrackingArea(rect: bounds,
      options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
      owner: controller, userInfo: ["obj": 0]))
  }
}
