//
//  PrefOSCToolbarSettingsSheetController.swift
//  iina
//
//  Created by Collider LI on 4/2/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

extension NSPasteboard.PasteboardType {
  static let iinaOSCToolbarButtonType = NSPasteboard.PasteboardType("com.collider.iina.oscToolbarButtonType")
}

class PrefOSCToolbarSettingsSheetController: NSWindowController {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("PrefOSCToolbarSettingsSheetController")
  }

  private var itemViewControllers: [PrefOSCToolbarDraggingItemViewController] = []

  @IBOutlet weak var availableItemsView: PrefOSCToolbarAvailableItemsView!
  @IBOutlet weak var currentItemsView: PrefOSCToolbarCurrentItemsView!

  override func windowDidLoad() {
    super.windowDidLoad()

    currentItemsView.wantsLayer = true
    currentItemsView.layer?.backgroundColor = NSColor.secondarySelectedControlColor.cgColor
    currentItemsView.layer?.cornerRadius = 4
    currentItemsView.registerForDraggedTypes([.iinaOSCToolbarButtonType])
    currentItemsView.updateItems()

    let allButtonTypes: [Preference.ToolBarButton] = [.settings, .playlist, .pip, .fullScreen, .musicMode, .subTrack]
    for type in allButtonTypes {
      let itemViewController = PrefOSCToolbarDraggingItemViewController(buttonType: type)
      itemViewControllers.append(itemViewController)
      availableItemsView.addView(itemViewController.view, in: .top)
      Utility.quickConstraints(["H:[v(240)]", "V:[v(24)]"], ["v": itemViewController.view])
    }
  }

  @IBAction func okButtonAction(_ sender: Any) {
    window!.sheetParent!.endSheet(window!)
    window!.orderOut(nil)
  }
}


class PrefOSCToolbarCurrentItemsView: NSStackView, NSDraggingSource {

  var items: [Preference.ToolBarButton] = [.settings, .playlist, .pip]

  private let placeholderView: NSView = NSView()
  private var dragDestIndex: Int = 0

  func updateItems() {
    views.forEach { self.removeView($0) }
    for buttonType in items {
      let button = NSImageView()
      button.image = buttonType.image()
      self.addView(button, in: .trailing)
      Utility.quickConstraints(["H:[btn(24)]", "V:[btn(24)]"], ["btn": button])
    }
  }

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    return .delete
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    print(screenPoint, operation)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    // don't accept existing items
    guard let rawButtonType = sender.draggingPasteboard().propertyList(forType: .iinaOSCToolbarButtonType) as? Int,
      let buttonType = Preference.ToolBarButton(rawValue: rawButtonType),
      !items.contains(buttonType) else {
      return []
    }
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    // don't accept existing items
    guard let rawButtonType = sender.draggingPasteboard().propertyList(forType: .iinaOSCToolbarButtonType) as? Int,
      let buttonType = Preference.ToolBarButton(rawValue: rawButtonType),
      !items.contains(buttonType) else {
        return []
    }

    // get the expected drag destination position and index
    let pos = convert(sender.draggingLocation(), from: nil)
    let index = views.count - Int(floor((frame.width - pos.x) / 24)) - 1
    dragDestIndex = index
    // add placeholder view at expected index
    if views.contains(placeholderView) {
      removeView(placeholderView)
    }
    Utility.quickConstraints(["H:[v(24)]", "V:[v(24)]"], ["v": placeholderView])
    insertView(placeholderView, at: index, in: .trailing)
    // animate frames
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.25
      context.allowsImplicitAnimation = true
      self.layoutSubtreeIfNeeded()
    }, completionHandler: nil)

    return .copy
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    // remove the placeholder view
    if views.contains(placeholderView) {
      removeView(placeholderView)
    }
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if let rawButtonType = sender.draggingPasteboard().propertyList(forType: .iinaOSCToolbarButtonType) as? Int,
      let buttonType = Preference.ToolBarButton(rawValue: rawButtonType) {
      let button = NSImageView()
      button.image = buttonType.image()
      Utility.quickConstraints(["H:[btn(24)]", "V:[btn(24)]"], ["btn": button])
      insertView(button, at: dragDestIndex, in: .trailing)
      return true
    }
    return false
  }

}


class PrefOSCToolbarAvailableItemsView: NSStackView, NSDraggingSource {

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    return .copy
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    print(screenPoint, operation)
  }

}
