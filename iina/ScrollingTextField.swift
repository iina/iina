//
//  ScrollingTextField.swift
//  IINA
//
//  Created by Yuze Jiang on 7/28/18.
//  Copyright © 2018 Yuze Jiang. All rights reserved.
//

import Cocoa

class ScrollingTextField: NSTextField {

  enum State {
    case idle
    case pause
    case scroll
  }

  private var state: State = .idle

  let frequency: TimeInterval = 0.03

  private var scrollingTimer: Timer?
  private var pauseTimer: Timer?
  private var point: NSPoint = .zero

  private var increment: CGFloat = 1

  private var scrollingString = NSAttributedString(string: "")
  private var addedStringWidth: CGFloat = 0

  override var stringValue: String {
    didSet {
      reset()
    }
  }

  func scroll() {
    let stringWidth = attributedStringValue.size().width
    guard state == .idle && stringWidth > 252 else { return }

    state = .pause
    pauseTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(startScrolling),
                                      userInfo: nil, repeats: false)
  }

  @objc
  private func startScrolling() {
    let attributes = attributedStringValue.attributes(at: 0, effectiveRange: nil)
    let addedString = stringValue + "    "
    addedStringWidth = NSAttributedString(string: addedString, attributes: attributes).size().width
    scrollingString = NSAttributedString(string: addedString + stringValue, attributes: attributes)
    state = .scroll
    scrollingTimer = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(moveText),
                                          userInfo: nil, repeats: true)
  }

  private func reset() {
    scrollingTimer?.invalidate()
    scrollingTimer = nil
    pauseTimer?.invalidate()
    pauseTimer = nil
    point = .zero
    state = .idle
    needsDisplay = true
  }

  @objc
  private func moveText() {
    point.x -= increment
    if point.x + addedStringWidth < 0 {
      reset()
      return
    }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    if state == .scroll {
      scrollingString.draw(at: point)
    } else {
      attributedStringValue.draw(at: point)
    }
  }

}
