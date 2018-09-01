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

  let updateInterval: TimeInterval = 0.03
  let timeToWaitBeforeStart: TimeInterval = 0.2

  private var scrollingTimer: Timer?
  private var startTimer: Timer?
  private var drawPoint: NSPoint = .zero

  private var step: CGFloat = 1

  private var scrollingString = NSAttributedString(string: "")
  private var appendedStringCopyWidth: CGFloat = 0

  override var stringValue: String {
    didSet {
      reset()
    }
  }

  func scroll() {
    let stringWidth = attributedStringValue.size().width
    // FIXME: Use hard-coded width here. Should be changed to frame.width and handle the center alignment by ourself in draw().
    guard state == .idle && stringWidth > 252 else { return }

    state = .pause
    startTimer = Timer.scheduledTimer(timeInterval: timeToWaitBeforeStart, target: self, selector: #selector(startScrolling),
                                      userInfo: nil, repeats: false)
  }

  @objc
  private func startScrolling() {
    let attributes = attributedStringValue.attributes(at: 0, effectiveRange: nil)
    // Add padding between end and start of the copy
    let appendedStringCopy = "    " + stringValue
    appendedStringCopyWidth = NSAttributedString(string: appendedStringCopy, attributes: attributes).size().width
    scrollingString = NSAttributedString(string: stringValue + appendedStringCopy, attributes: attributes)
    state = .scroll
    scrollingTimer = Timer.scheduledTimer(timeInterval: updateInterval, target: self, selector: #selector(moveText),
                                          userInfo: nil, repeats: true)
  }

  private func reset() {
    scrollingTimer?.invalidate()
    scrollingTimer = nil
    startTimer?.invalidate()
    startTimer = nil
    drawPoint = .zero
    state = .idle
    needsDisplay = true
  }

  @objc
  private func moveText() {
    drawPoint.x -= step
    if drawPoint.x + appendedStringCopyWidth < 0 {
      reset()
      return
    }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    if state == .scroll {
      scrollingString.draw(at: drawPoint)
    } else {
      attributedStringValue.draw(at: drawPoint)
    }
  }

}
