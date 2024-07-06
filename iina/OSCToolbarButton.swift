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
  static func setStyle(of toolbarButton: NSButton, buttonType: Preference.ToolBarButton) {
    toolbarButton.translatesAutoresizingMaskIntoConstraints = false
    toolbarButton.bezelStyle = .regularSquare
    toolbarButton.image = buttonType.image()
    toolbarButton.isBordered = false
    toolbarButton.tag = buttonType.rawValue
    toolbarButton.refusesFirstResponder = true
    toolbarButton.toolTip = buttonType.description()
    let sideSize = Preference.ToolBarButton.frameHeight
    Utility.quickConstraints(["H:[btn(\(sideSize))]", "V:[btn(\(sideSize))]"], ["btn": toolbarButton])
  }

  static func buildDragItem(from toolbarButton: NSButton, pasteboardWriter: NSPasteboardWriting,
                            buttonType: Preference.ToolBarButton) -> NSDraggingItem? {
    // seems to be the only reliable way to get image size
    guard let imgReps = toolbarButton.image?.representations else { return nil }
    guard !imgReps.isEmpty else { return nil }
    let imageSize = imgReps[0].size

    let dragItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
    let iconSize = Preference.ToolBarButton.frameHeight
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
