//
//  OSCToolbarButton.swift
//  iina
//
//  Created by Matt Svoboda on 11/6/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Cocoa

class OSCToolbarButton: NSButton {
  private var hoverArea: NSTrackingArea?
  private var isHovered = false
  private var isPressed = false
  private var isSendingAction = false
  private var inactiveImage: NSImage?
  private var activeImage: NSImage?
  private(set) var isActive = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configureFeedback()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureFeedback()
  }

  private func configureFeedback() {
    let feedbackCell = OSCToolbarButtonCell(textCell: "")
    cell = feedbackCell
    setButtonType(.momentaryPushIn)
    feedbackCell.highlightsBy = []
    feedbackCell.showsStateBy = []
    feedbackCell.imageDimsWhenDisabled = false
    imagePosition = .imageOnly
    contentTintColor = .white
    wantsLayer = true
    layer?.masksToBounds = false
    layer?.shadowColor = NSColor.white.cgColor
    layer?.shadowOffset = .zero
    layer?.shadowRadius = 4
    updateFeedback(animated: false)
  }

  func setActive(_ active: Bool) {
    guard isActive != active else { return }
    isActive = active
    updateFeedback()
  }

  override var isEnabled: Bool {
    didSet {
      if !isEnabled { isHovered = false; isPressed = false }
      updateFeedback(animated: false)
    }
  }

  override var isHidden: Bool {
    didSet {
      if isHidden { isHovered = false; isPressed = false }
      updateFeedback(animated: false)
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    isHovered = false
    isPressed = false
    updateFeedback(animated: false)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero,
      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
    addTrackingArea(area)
    hoverArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    guard isEnabled else { return }
    isHovered = true
    updateFeedback()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    updateFeedback()
  }

  fileprivate func setPressed(_ pressed: Bool) {
    isPressed = pressed && isEnabled
    updateFeedback(animated: !pressed)
  }

  override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
    let wasSendingAction = isSendingAction
    isSendingAction = true
    updateFeedback(animated: false)
    displayIfNeeded()
    defer {
      isSendingAction = wasSendingAction
      updateFeedback()
    }
    return super.sendAction(action, to: target)
  }

  private func updateFeedback(animated: Bool = true) {
    let pressed = isPressed || isSendingAction
    let highlighted = isActive || (isEnabled && pressed)
    image = highlighted ? activeImage ?? inactiveImage : inactiveImage
    needsDisplay = true
    guard let layer else { return }
    let opacity: Float = !isEnabled ? 0.35 : isHovered || pressed ? 1 : isActive ? 0.94 : 0.68
    let glow: Float = !isEnabled ? 0 : pressed ? 0.75 : isHovered ? 0.5 : 0
    let duration = animated && !AccessibilityPreferences.motionReductionEnabled ?
      AccessibilityPreferences.adjustedDuration(isHovered ? 0.10 : 0.14) : 0
    let previousOpacity = layer.presentation()?.opacity ?? layer.opacity
    let previousGlow = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity
    let opacityChanged = layer.opacity != opacity
    let glowChanged = layer.shadowOpacity != glow
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    alphaValue = CGFloat(opacity)
    layer.opacity = opacity
    layer.shadowOpacity = glow
    CATransaction.commit()
    for (key, changed, from, to) in [("opacity", opacityChanged, previousOpacity, opacity),
                                    ("shadowOpacity", glowChanged, previousGlow, glow)] {
      let animationKey = "toolbarFeedback.\(key)"
      guard changed || duration == 0 else { continue }
      layer.removeAnimation(forKey: animationKey)
      guard duration > 0 else { continue }
      let animation = CABasicAnimation(keyPath: key)
      animation.fromValue = from
      animation.toValue = to
      animation.duration = duration
      animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
      layer.add(animation, forKey: animationKey)
    }
  }
  
  /// - Parameters:
  ///   - reducedWidth: For the current OSC design, the width need to be compressed when there are five buttons in the floating OSC
  static func setStyle(of toolbarButton: NSButton, buttonType: Preference.ToolBarButton, reducedWidth: Bool = false) {
    toolbarButton.translatesAutoresizingMaskIntoConstraints = false
    toolbarButton.bezelStyle = .regularSquare
    toolbarButton.image = buttonType.image()
    toolbarButton.isBordered = false
    toolbarButton.tag = buttonType.rawValue
    toolbarButton.refusesFirstResponder = true
    toolbarButton.toolTip = buttonType.localizedDescription()
    let buttonHeight = Preference.ToolBarButton.frameSize
    let buttonWidth = reducedWidth ? Preference.ToolBarButton.compactFrameWidth : Preference.ToolBarButton.frameSize
    toolbarButton.size(width: buttonWidth, height: buttonHeight)
    if let button = toolbarButton as? OSCToolbarButton {
      button.inactiveImage = toolbarButton.image
      button.activeImage = buttonType.alternateImage()
      button.updateFeedback(animated: false)
    }
  }

  static func buildDragItem(from toolbarButton: NSButton, pasteboardWriter: NSPasteboardWriting,
                            buttonType: Preference.ToolBarButton) -> NSDraggingItem? {
    // seems to be the only reliable way to get image size
    guard let imageSize = toolbarButton.image?.representations[at: 0]?.size else { return nil }

    let dragItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
    let iconSize = Preference.ToolBarButton.frameSize
    // Image is centered in frame, and frame has 0px offset from left & bottom of superview
    let dragOrigin = CGPoint(x: (iconSize - imageSize.width) / 2, y: (iconSize - imageSize.height) / 2)
    dragItem.draggingFrame = NSRect(origin: dragOrigin, size: imageSize)
    Logger.log("Dragging from AvailableItemsView: \(dragItem.draggingFrame) (imageSize: \(imageSize))")
    dragItem.imageComponentsProvider = {
      let imageComponent = NSDraggingImageComponent(key: .icon)
      let image = buttonType.image().tinted(.textColor)
      imageComponent.contents = image
      imageComponent.frame = NSRect(origin: .zero, size: imageSize)
      return [imageComponent]
    }

    return dragItem
  }
}

private final class OSCToolbarButtonCell: NSButtonCell {
  override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
    (controlView as? OSCToolbarButton)?.setPressed(flag)
    super.highlight(flag, withFrame: cellFrame, in: controlView)
  }
}
