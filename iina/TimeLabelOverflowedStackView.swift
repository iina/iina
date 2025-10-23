//
//  TimeLabelOverflowedStackView.swift
//  iina
//
//  Created by lhc on 5/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class TimeLabelOverflowedStackView: NSStackView {

  override var alignmentRectInsets: NSEdgeInsets {
    return NSEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)
  }

  /// Informs the receiver that the user has pressed the left mouse button.
  ///
  /// This is a workaround for IINA issue #5768 where starting with macOS Tahoe AppKit is miss-handling mouse events in certain
  /// circumstances. Merely adding this function solved the problem. Maybe the presence of this function prevents the use of some sort
  /// of faulty optimization?
  /// - Important: _DO NOT REMOVE_ this function thinking it is not needed. Read issue #5768.
  /// - Parameter event: An object encapsulating information about the mouse-down event.
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
  }
}
