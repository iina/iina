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

    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.secondarySelectedControlColor.cgColor
    view.layer?.cornerRadius = 4

    iconImageView.image = buttonType.image()
    descriptionLabel.stringValue = buttonType.description()
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.iinaOSCToolbarButtonType]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    if type == .iinaOSCToolbarButtonType {
      return buttonType.rawValue
    }
    return nil
  }

  override func mouseDown(with event: NSEvent) {
    let dragItem = NSDraggingItem(pasteboardWriter: self)
    dragItem.draggingFrame = NSRect(origin: view.convert(event.locationInWindow, from: nil),
                                    size: NSSize(width: 24, height: 24))
    dragItem.imageComponentsProvider = {
      let imageComponent = NSDraggingImageComponent(key: .icon)
      imageComponent.contents = self.buttonType.image()
      imageComponent.frame = NSRect(origin: .zero, size: NSSize(width: 14, height: 14))
      return [imageComponent]
    }
    view.beginDraggingSession(with: [dragItem], event: event, source: view.superview as! PrefOSCToolbarAvailableItemsView)
  }

}
