//
//  PrefOSCToolbarDraggingItemViewController.swift
//  iina
//
//  Created by Collider LI on 4/2/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PrefOSCToolbarDraggingItemViewController: NSViewController, NSPasteboardWriting {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefOSCToolbarDraggingItemViewController")
  }

  var availableItemsView: PrefOSCToolbarAvailableItemsView?
  var buttonType: Preference.ToolBarButton

  @IBOutlet weak var iconImageView: NSImageView!
  @IBOutlet weak var descriptionLabel: NSTextField!


  init(buttonType: Preference.ToolBarButton) {
    self.buttonType = buttonType
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    iconImageView.image = buttonType.image()
    iconImageView.translatesAutoresizingMaskIntoConstraints = false
    descriptionLabel.stringValue = buttonType.description()
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.iinaOSCAvailableToolbarButtonType]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    if type == .iinaOSCAvailableToolbarButtonType {
      return buttonType.rawValue
    }
    return nil
  }

  override func mouseDown(with event: NSEvent) {
    let dragItem = NSDraggingItem(pasteboardWriter: self)
    dragItem.draggingFrame = NSRect(origin: view.convert(event.locationInWindow, from: nil),
                                    size: NSSize(width: Preference.ToolBarButton.frameHeight, height: Preference.ToolBarButton.frameHeight))
    dragItem.imageComponentsProvider = {
      let imageComponent = NSDraggingImageComponent(key: .icon)
      let image = self.buttonType.image()
      imageComponent.contents = image
      imageComponent.frame = NSRect(origin: .zero, size: NSSize(width: image.size.width, height: image.size.height))
      return [imageComponent]
    }
    if let availableItemsView = availableItemsView {
      view.beginDraggingSession(with: [dragItem], event: event, source: availableItemsView)
    }
  }

}
