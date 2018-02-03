//
//  PrefOSCToolbarSettingsSheetController.swift
//  iina
//
//  Created by Collider LI on 4/2/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

extension NSPasteboard.PasteboardType {
  static let iinaOSCAvailableToolbarButtonType = NSPasteboard.PasteboardType("com.collider.iina.iinaOSCAvailableToolbarButtonType")
  static let iinaOSCCurrentToolbarButtonType = NSPasteboard.PasteboardType("com.collider.iina.iinaOSCCurrentToolbarButtonType")
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
    currentItemsView.registerForDraggedTypes([.iinaOSCAvailableToolbarButtonType, .iinaOSCCurrentToolbarButtonType])
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


class PrefOSCToolbarCurrentItem: NSImageView, NSPasteboardWriting {

  var buttonType: Preference.ToolBarButton

  init(buttonType: Preference.ToolBarButton) {
    self.buttonType = buttonType
    super.init(frame: .zero)
    self.image = buttonType.image()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.iinaOSCCurrentToolbarButtonType]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    if type == .iinaOSCCurrentToolbarButtonType {
      return buttonType.rawValue
    }
    return nil
  }

  override func mouseDown(with event: NSEvent) {
    let dragItem = NSDraggingItem(pasteboardWriter: self)
    dragItem.draggingFrame = NSRect(origin: convert(event.locationInWindow, from: nil),
                                    size: NSSize(width: 24, height: 24))
    dragItem.imageComponentsProvider = {
      let imageComponent = NSDraggingImageComponent(key: .icon)
      imageComponent.contents = self.buttonType.image()
      imageComponent.frame = NSRect(origin: .zero, size: NSSize(width: 14, height: 14))
      return [imageComponent]
    }

    let currentItemsView = superview as! PrefOSCToolbarCurrentItemsView
    currentItemsView.itemBeingDragged = self
    beginDraggingSession(with: [dragItem], event: event, source: currentItemsView)
  }

}


class PrefOSCToolbarCurrentItemsView: NSStackView, NSDraggingSource {

  var items: [Preference.ToolBarButton] = [.settings, .playlist, .pip]

  var itemBeingDragged: PrefOSCToolbarCurrentItem?

  private let placeholderView: NSView = NSView()
  private var dragDestIndex: Int = 0

  func updateItems() {
    views.forEach { self.removeView($0) }
    for buttonType in items {
      let item = PrefOSCToolbarCurrentItem(buttonType: buttonType)
      self.addView(item, in: .trailing)
      Utility.quickConstraints(["H:[btn(24)]", "V:[btn(24)]"], ["btn": item])
    }
  }

  // Dragging source

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    return [.delete, .move]
  }

  func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
    if let itemBeingDragged = itemBeingDragged {
      // remove the dragged view and insert a placeholder at its position.
      let index = views.index(of: itemBeingDragged)!
      removeView(itemBeingDragged)
      Utility.quickConstraints(["H:[v(24)]", "V:[v(24)]"], ["v": placeholderView])
      insertView(placeholderView, at: index, in: .trailing)
    }
  }

  func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
    guard let window = window else { return }
    let windowPoint = window.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
    let inView = frame.contains(windowPoint)
    session.animatesToStartingPositionsOnCancelOrFail = inView
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    if operation == .delete,
      let rawButtonType = session.draggingPasteboard.propertyList(forType: .iinaOSCCurrentToolbarButtonType) as? Int,
      let buttonType = Preference.ToolBarButton(rawValue: rawButtonType),
      let index = items.index(of: buttonType) {
      items.remove(at: index)
    }
  }

  // Dragging destination

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let pboard = sender.draggingPasteboard()

    if let _ = pboard.availableType(from: [.iinaOSCAvailableToolbarButtonType]) {
      // dragging available item in; don't accept existing items
      guard let rawButtonType = sender.draggingPasteboard().propertyList(forType: .iinaOSCAvailableToolbarButtonType) as? Int,
        let buttonType = Preference.ToolBarButton(rawValue: rawButtonType),
        !items.contains(buttonType) else {
        return []
      }
      return .copy
    } else if let _ = pboard.availableType(from: [.iinaOSCCurrentToolbarButtonType]) {
      // rearranging current items
      return .move
    }

    return []
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    let pboard = sender.draggingPasteboard()

    let isAvailableItem = pboard.availableType(from: [.iinaOSCAvailableToolbarButtonType]) != nil
    let isCurrentItem = pboard.availableType(from: [.iinaOSCCurrentToolbarButtonType]) != nil
    guard isAvailableItem || isCurrentItem else { return [] }

    if isAvailableItem {
      // dragging available item in; don't accept existing items
      guard let rawButtonType = sender.draggingPasteboard().propertyList(forType: .iinaOSCAvailableToolbarButtonType) as? Int,
        let buttonType = Preference.ToolBarButton(rawValue: rawButtonType),
        !items.contains(buttonType) else {
          return []
      }
    }

    // get the expected drag destination position and index
    let pos = convert(sender.draggingLocation(), from: nil)
    var index = views.count - Int(floor((frame.width - pos.x) / 24)) - 1
    if index < 0 { index = 0 }
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

    return isAvailableItem ? .copy : .move
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    // remove the placeholder view
    if views.contains(placeholderView) {
      removeView(placeholderView)
    }
    itemBeingDragged = nil
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let pboard = sender.draggingPasteboard()

    if let _ = pboard.availableType(from: [.iinaOSCAvailableToolbarButtonType]) {
      // dragging available item in; don't accept existing items
      if let rawButtonType = sender.draggingPasteboard().propertyList(forType: .iinaOSCAvailableToolbarButtonType) as? Int,
        let buttonType = Preference.ToolBarButton(rawValue: rawButtonType),
        dragDestIndex >= 0, dragDestIndex < views.count {
        let item = PrefOSCToolbarCurrentItem(buttonType: buttonType)
        item.image = buttonType.image()
        Utility.quickConstraints(["H:[btn(24)]", "V:[btn(24)]"], ["btn": item])
        insertView(item, at: dragDestIndex, in: .trailing)
        return true
      }
      return false
    } else if let _ = pboard.availableType(from: [.iinaOSCCurrentToolbarButtonType]) {
      // rearranging current items
      insertView(itemBeingDragged!, at: dragDestIndex, in: .trailing)
      return true
    }

    return false
  }

}


class PrefOSCToolbarAvailableItemsView: NSStackView, NSDraggingSource {

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    return .copy
  }

}
