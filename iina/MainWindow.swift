//
//  MainWindow.swift
//  iina
//
//  Created by Collider LI on 10/1/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

/// Keep the mouse-down resize axis for the whole drag; corners use X and horizontal edges use Y.
struct WindowResizeSession {
  private let initialSize: NSSize
  private let initialMouse: NSPoint
  private let aspect: CGFloat
  private let horizontal: Bool
  private let direction: CGFloat

  init?(frame: NSRect, mouse: NSPoint, aspectRatio: NSSize) {
    guard aspectRatio.width > 0, aspectRatio.height > 0,
          aspectRatio.width.isFinite, aspectRatio.height.isFinite else { return nil }
    let grip: CGFloat = 20
    guard frame.insetBy(dx: -grip, dy: -grip).contains(mouse) else { return nil }
    if abs(mouse.x - frame.minX) <= grip {
      horizontal = true
      direction = -1
    } else if abs(mouse.x - frame.maxX) <= grip {
      horizontal = true
      direction = 1
    } else if abs(mouse.y - frame.minY) <= grip {
      horizontal = false
      direction = -1
    } else if abs(mouse.y - frame.maxY) <= grip {
      horizontal = false
      direction = 1
    } else {
      return nil
    }
    initialSize = frame.size
    initialMouse = mouse
    aspect = aspectRatio.width / aspectRatio.height
  }

  func size(at mouse: NSPoint, maximum: NSSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)) -> NSSize {
    let ratio = horizontal ? aspect : 1 / aspect
    let initialPrimary = horizontal ? initialSize.width : initialSize.height
    let initialSecondary = horizontal ? initialSize.height : initialSize.width
    let primaryLimit = horizontal ? maximum.width : maximum.height
    let secondaryLimit = horizontal ? maximum.height : maximum.width
    let maximumPrimary = min(primaryLimit, max(initialPrimary, secondaryLimit * ratio))
    let displacement = direction * (horizontal ? mouse.x - initialMouse.x : mouse.y - initialMouse.y)
    let primary = min(maximumPrimary, max(1, initialPrimary + displacement))
    let delta = primary - initialPrimary
    let padding = initialSecondary - initialPrimary / ratio
    var secondary = initialSecondary + delta / ratio
    if delta > 0, padding > 0 {
      // Keep the ungrabbed dimension until the video aspect catches up with it.
      secondary = max(initialSecondary, primary / ratio)
    } else if delta > 0, padding < 0 {
      // A minimum-clamped window can start narrower on the ungrabbed axis.
      // Consume that mismatch over the equivalent pointer distance, without
      // moving the grabbed edge or introducing a jump on the first resize tick.
      let progress = min(1, delta / (-padding * ratio))
      let eased = progress * progress * (3 - 2 * progress)
      secondary = primary / ratio + padding * (1 - eased)
    }
    secondary = min(secondaryLimit, max(1, secondary))
    return horizontal ? NSSize(width: primary, height: secondary) : NSSize(width: secondary, height: primary)
  }
}

class MainWindow: CommonWindow {
  var forceKeyAndMain = false
  override func sendEvent(_ event: NSEvent) {
    guard let controller = windowController as? MainWindowController, controller.isWindowLoaded else {
      super.sendEvent(event)
      return
    }
    if event.type == .leftMouseDown { controller.cancelWindowDrag() }
    defer {
      if event.type == .leftMouseUp {
        // OSC mouseUp must finish its drag before a background click can hide it.
        _ = controller.sidebars.handlePanelMouseEvent(event)
        controller.cancelWindowDrag()
      }
    }
    if event.type == .keyDown, controller.handleDefaultEscape(with: event) { return }
    if event.type != .leftMouseUp, controller.sidebars.handlePanelMouseEvent(event) { return }
    if controller.titleBarView?.handleBackgroundMouseEvent(event) == true { return }
    super.sendEvent(event)
  }

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
    // Focused tables must receive arrows before menu equivalents turn them into volume/seek commands.
    if let table = firstResponder as? NSTableView, (123...126).contains(event.keyCode) {
      table.keyDown(with: event)
      return true
    }
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
    guard let controller = window?.windowController as? MainWindowController else { return }
    for side in [SidebarController.Side.leading, .trailing] where controller.sidebars.sideBar(for: side).status != .hidden {
      addCursorRect(controller.sidebars.resizeHandleRect(for: side), cursor: .resizeLeftRight)
    }
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
