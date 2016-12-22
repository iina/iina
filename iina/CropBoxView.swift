//
//  CropBoxView.swift
//  iina
//
//  Created by lhc on 22/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class CropBoxView: NSView {
  
  private let boxStrokeColor = NSColor(calibratedRed: 0.4, green: 0.8, blue: 1, alpha: 1)
  private let boxFillColor = NSColor(calibratedWhite: 0.5, alpha: 0.3)
  
  weak var settingsViewController: CropSettingsViewController!
  
  var actualSize: NSSize = NSSize()
  
  var videoRect: NSRect = NSRect() {
    didSet {
      boxRect = videoRect
      updateCursorRects()
    }
  }
  
  var boxRect: NSRect = NSRect() {
    didSet {
      // update selected rect
      let xScale = actualSize.width / videoRect.width
      let yScale = actualSize.height / videoRect.height
      var ix = (boxRect.origin.x - videoRect.origin.x) * xScale
      var iy = (boxRect.origin.y - videoRect.origin.y) * xScale
      var iw = boxRect.width * xScale
      var ih = boxRect.height * yScale
      if abs(ix) <= 4 { ix = 0 }
      if abs(iy) <= 4 { iy = 0 }
      if abs(iw + ix - actualSize.width) <= 4 { iw = actualSize.width - ix }
      if abs(ih + iy - actualSize.height) <= 4 { ih = actualSize.height - iy }
      selectedRect = NSMakeRect(ix, iy, iw, ih)
    }
  }
  
  var selectedRect: NSRect = NSRect() {
    didSet {
      settingsViewController.updateSelectedRect()
    }
  }
  
  private var isDragging: Bool = false
  private var dragSide: DragSide = .top
  
  private enum DragSide {
    case top, bottom, left, right
  }
  
  // top and botom are related to view's coordinate
  private var rectTop: NSRect!
  private var rectBottom: NSRect!
  private var rectLeft: NSRect!
  private var rectRight: NSRect!
  
  private var lastMousePos: NSPoint?
  
  
  override func mouseDown(with event: NSEvent) {
    let mousePos = convert(event.locationInWindow, from: nil)
    lastMousePos = mousePos
    
    if rectTop.contains(mousePos) {
      isDragging = true
      dragSide = .top
    } else if rectBottom.contains(mousePos) {
      isDragging = true
      dragSide = .bottom
    } else if rectLeft.contains(mousePos) {
      isDragging = true
      dragSide = .left
    } else if rectRight.contains(mousePos) {
      isDragging = true
      dragSide = .right
    } else {
      super.mouseDown(with: event)
    }
  }
  
  override func mouseDragged(with event: NSEvent) {
    if isDragging {
      let mousePos = convert(event.locationInWindow, from: nil).constrain(in: videoRect)
      
      switch dragSide {
      case .top:
        let diff = mousePos.y - lastMousePos!.y
        boxRect.origin.y += diff
        boxRect.size.height -= diff
        
      case .bottom:
        let diff = mousePos.y - lastMousePos!.y
        boxRect.size.height += diff
        
      case .right:
        let diff = mousePos.x - lastMousePos!.x
        boxRect.size.width += diff
        
      case .left:
        let diff = mousePos.x - lastMousePos!.x
        boxRect.origin.x += diff
        boxRect.size.width -= diff
      }
      needsDisplay = true
      updateCursorRects()
      lastMousePos = mousePos
    } else {
      super.mouseDragged(with: event)
    }
  }
  
  override func mouseUp(with event: NSEvent) {
    if isDragging {
      isDragging = false
    } else {
      super.mouseUp(with: event)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    boxStrokeColor.setStroke()
    boxFillColor.setFill()
    
    let path = NSBezierPath(rect: boxRect)
    path.lineWidth = 2
    path.fill()
    path.stroke()
    
  }
  
  override func resetCursorRects() {
    addCursorRect(rectTop, cursor: NSCursor.resizeUpDown())
    addCursorRect(rectBottom, cursor: NSCursor.resizeUpDown())
    addCursorRect(rectLeft, cursor: NSCursor.resizeLeftRight())
    addCursorRect(rectRight, cursor: NSCursor.resizeLeftRight())
  }
  
  func updateCursorRects() {
    let x = boxRect.origin.x
    let y = boxRect.origin.y
    let w = boxRect.width
    let h = boxRect.height
    
    rectTop = NSMakeRect(x, y-2, w, 4)
    rectBottom = NSMakeRect(x, y+h-2, w, 4)
    rectLeft = NSMakeRect(x-2, y+2, 4, h-4)
    rectRight = NSMakeRect(x+w-2, y+2, 4, h-4)
    
    window?.invalidateCursorRects(for: self)
  }
  
}
