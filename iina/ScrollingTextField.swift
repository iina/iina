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

  private var isScrolling: Bool = false

  private var scroller: Timer?
  private var point: NSPoint = .zero

  private var cachedStringWidth: CGFloat?
  private var cachedStringValue: String?

  private var increment: CGFloat = 1

  private var modifyInternally: Bool = false

  override var stringValue: String {
    didSet {
      guard !modifyInternally else { return }
      cachedStringValue = nil
      reset()
    }
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    startScrolling()
  }

  private func setStringValue(_ newValue: String) {
    modifyInternally = true
    stringValue = newValue
    modifyInternally = false
  }

  func scroll() {
    let stringWidth = attributedStringValue.size().width
    guard !isScrolling && stringWidth > frame.maxX else { return }

    isScrolling = true
    Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(startScrolling), userInfo: nil, repeats: false)
  }

  @objc
  private func startScrolling() {
    cachedStringValue = stringValue
    setStringValue(stringValue + "   ")
    cachedStringWidth = attributedStringValue.size().width
    setStringValue(stringValue + cachedStringValue!)
    scroller = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(moveText), userInfo: nil, repeats: true)
  }

  private func reset() {
    scroller?.invalidate()
    scroller = nil
    setStringValue(cachedStringValue ?? stringValue)
    cachedStringValue = nil
    cachedStringWidth = nil
    point = .zero
    isScrolling = false
    needsDisplay = true
  }

  @objc
  private func moveText() {
    guard let cachedStringWidth = cachedStringWidth else { return }
    point.x -= increment
    if point.x + cachedStringWidth < 0 {
      reset()
      return
    }
    needsDisplay = true
  }


  override func draw(_ dirtyRect: NSRect) {
    attributedStringValue.draw(at: point)
  }

}
