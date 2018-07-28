//
//  ScrollingTextField.swift
//  IINA
//
//  Created by Yuze Jiang on 7/28/18.
//  Copyright © 2018 Yuze Jiang. All rights reserved.
//

import Cocoa

class ScrollingTextField: NSTextField {

  let frequency: TimeInterval = 0.03

  var isScrolling: Bool = false

  private var scroller: Timer?
  private var point: NSPoint = .zero

  private var cachedStringWidth: CGFloat?
  private var cachedStringValue: String?

  private var increment: CGFloat = 1

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    startScrolling()
  }

  func startScrolling() {
    let stringWidth = attributedStringValue.size().width
    guard !isScrolling && stringWidth > frame.maxX else { return }
    cachedStringValue = stringValue
    stringValue += "  "
    cachedStringWidth = attributedStringValue.size().width
    stringValue += cachedStringValue!
    scroller = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(moveText), userInfo: nil, repeats: true)
    isScrolling = true
  }

  func reset() {
    scroller?.invalidate()
    scroller = nil
    stringValue = cachedStringValue ?? stringValue
    cachedStringValue = nil
    cachedStringWidth = nil
    point = .zero
    isScrolling = false
    needsDisplay = true
  }

  @objc
  private func moveText() {
    point.x -= increment
    if point.x + cachedStringWidth! < 0 {
      reset()
      return
    }
    needsDisplay = true
  }


  override func draw(_ dirtyRect: NSRect) {
    attributedStringValue.draw(at: point)
  }

}
