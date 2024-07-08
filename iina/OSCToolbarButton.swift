//
//  OSCToolbarButton.swift
//  iina
//
//  Created by Matt Svoboda on 11/6/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Not elegant. Just a place to stick common code so that it won't be duplicated
class OSCToolbarButton {
  
  /// - Parameters:
  ///   - reducedWidth: For the current OSC design, the width need to be compressed when there are five buttons in the floating OSC
  static func setStyle(of toolbarButton: NSButton, buttonType: Preference.ToolBarButton, reducedWidth: Bool = false) {
    toolbarButton.translatesAutoresizingMaskIntoConstraints = false
    toolbarButton.bezelStyle = .regularSquare
    toolbarButton.image = buttonType.image()
    toolbarButton.isBordered = false
    toolbarButton.tag = buttonType.rawValue
    toolbarButton.refusesFirstResponder = true
    toolbarButton.toolTip = buttonType.description()
    let buttonHeight = Preference.ToolBarButton.frameSize
    let buttonWidth = reducedWidth ? Preference.ToolBarButton.compactFrameWidth : Preference.ToolBarButton.frameSize
    Utility.quickConstraints(["H:[btn(\(buttonWidth))]", "V:[btn(\(buttonHeight))]"], ["btn": toolbarButton])
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
