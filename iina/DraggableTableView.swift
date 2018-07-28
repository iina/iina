//
//  DraggableTableView.swift
//  iina
//
//  Created by sidneys on 01.02.18.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class DraggableTableView: NSTableView {

  // MARK: - Attributes

  override func acceptsFirstMouse(for theEvent: NSEvent?) -> Bool {
    return true
  }

  // MARK: - Methods

  override func mouseDown(with theEvent: NSEvent) {

    let globalLocation = theEvent.locationInWindow
    let localLocation = convert(globalLocation, from: nil)
    let clickedRow = row(at: localLocation)

    if clickedRow > -1 {
      // Populated row: Select item
      selectRowIndexes(NSIndexSet(index: clickedRow) as IndexSet, byExtendingSelection: false)
    } else {
      // Empty row: Drag window
      if #available(OSX 10.11, *) {
        window?.performDrag(with: theEvent)
      }
    }

    super.mouseDown(with: theEvent)
  }
}
