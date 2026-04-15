//
//  ControlBarView.swift
//  iina
//
//  Created by lhc on 16/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

// MARK: - Draggable Glass Effect View

/// NSGlassEffectView subclass that forwards background-drag events to a ControlBarView.
/// Button/slider clicks pass through to subviews normally; only empty-area drags are forwarded.
@available(macOS 26, *)
class DraggableGlassEffectView: NSGlassEffectView {
  weak var controlBar: ControlBarView?

  override func mouseDown(with event: NSEvent) {
    controlBar?.handleDragMouseDown(in: self, with: event)
  }
  override func mouseDragged(with event: NSEvent) {
    controlBar?.handleDragMouseDragged(in: self, with: event)
  }
  override func mouseUp(with event: NSEvent) {
    controlBar?.handleDragMouseUp(in: self)
  }
}

// MARK: - ControlBarView

class ControlBarView: NSVisualEffectView {

  @IBOutlet weak var xConstraint: NSLayoutConstraint!
  @IBOutlet weak var yConstraint: NSLayoutConstraint!

  var mousePosRelatedToView: CGPoint?

  var isDragging: Bool = false

  private var isAlignFeedbackSent = false
  private(set) var glassView: NSView?

  override func awakeFromNib() {
    if #available(macOS 26, *) {
      // Glass setup deferred to setupLiquidGlass() called from MainWindowController
    } else {
      self.roundCorners(withRadius: 6)
    }
    self.translatesAutoresizingMaskIntoConstraints = false
  }

  /// Replace the NSVisualEffectView background with Liquid Glass on macOS 26+.
  func setupLiquidGlass() {
    if #available(macOS 26, *) {
      guard let parent = self.superview, glassView == nil else { return }

      let glass = DraggableGlassEffectView()
      glass.controlBar = self
      glass.alphaValue = 0.6
      glass.cornerRadius = 10
      glass.translatesAutoresizingMaskIntoConstraints = false
      parent.addSubview(glass, positioned: .above, relativeTo: self)
      NSLayoutConstraint.activate([
        glass.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        glass.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        glass.topAnchor.constraint(equalTo: self.topAnchor),
        glass.bottomAnchor.constraint(equalTo: self.bottomAnchor),
      ])

      // Migrate subviews and their constraints into the glass view
      let subviewsToMove = Array(self.subviews)
      let constraintsToMigrate = self.constraints.filter { c in
        subviewsToMove.contains(where: { c.firstItem === $0 || c.secondItem === $0 })
      }
      for subview in subviewsToMove {
        glass.addSubview(subview)
      }
      for old in constraintsToMigrate {
        let first: AnyObject = (old.firstItem === self) ? glass : old.firstItem ?? glass
        let second: AnyObject? = (old.secondItem === self) ? glass : old.secondItem
        let migrated = NSLayoutConstraint(
          item: first, attribute: old.firstAttribute,
          relatedBy: old.relation,
          toItem: second, attribute: old.secondAttribute,
          multiplier: old.multiplier, constant: old.constant)
        migrated.priority = old.priority
        migrated.isActive = true
      }

      self.isHidden = true
      self.glassView = glass
    }
  }

  // MARK: - Drag handling

  func handleDragMouseDown(in view: NSView, with event: NSEvent) {
    mousePosRelatedToView = NSEvent.mouseLocation
    mousePosRelatedToView!.x -= view.frame.origin.x
    mousePosRelatedToView!.y -= view.frame.origin.y
    isAlignFeedbackSent = abs(view.frame.origin.x - (view.window!.frame.width - view.frame.width) / 2) <= 5
    isDragging = true
  }

  func handleDragMouseDragged(in view: NSView, with event: NSEvent) {
    guard let mousePos = mousePosRelatedToView, let windowFrame = view.window?.frame else { return }
    let currentLocation = NSEvent.mouseLocation
    var newOrigin = CGPoint(
      x: currentLocation.x - mousePos.x,
      y: currentLocation.y - mousePos.y
    )
    // stick to center
    if Preference.bool(for: .controlBarStickToCenter) {
      let xPosWhenCenter = (windowFrame.width - view.frame.width) / 2
      if abs(newOrigin.x - xPosWhenCenter) <= 5 {
        newOrigin.x = xPosWhenCenter
        if !isAlignFeedbackSent {
          NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
          isAlignFeedbackSent = true
        }
      } else {
        isAlignFeedbackSent = false
      }
    }
    // bound to window frame
    let xMax = windowFrame.width - view.frame.width - 10
    let yMax = windowFrame.height - view.frame.height - 25
    newOrigin = newOrigin.constrained(to: NSRect(x: 10, y: 0, width: xMax, height: yMax))
    // apply position
    let newConstraint = newOrigin.x + view.frame.width / 2
    xConstraint.constant = view.userInterfaceLayoutDirection == .rightToLeft ?
      windowFrame.width - newConstraint : newConstraint
    yConstraint.constant = newOrigin.y
  }

  func handleDragMouseUp(in view: NSView) {
    isDragging = false
    guard let windowFrame = view.window?.frame else { return }
    Preference.set(xConstraint.constant / windowFrame.width, for: .controlBarPositionHorizontal)
    Preference.set(yConstraint.constant / windowFrame.height, for: .controlBarPositionVertical)
  }

  // Legacy path (macOS < 26)
  override func mouseDown(with event: NSEvent) {
    handleDragMouseDown(in: self, with: event)
  }
  override func mouseDragged(with event: NSEvent) {
    handleDragMouseDragged(in: self, with: event)
  }
  override func mouseUp(with event: NSEvent) {
    handleDragMouseUp(in: self)
  }

}
