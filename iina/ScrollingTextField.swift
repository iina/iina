//
//  ScrollingTextField.swift
//  IINA
//
//  Created by Yuze Jiang on 7/28/18.
//  Copyright © 2018 Yuze Jiang. All rights reserved.
//

import Cocoa

// Adjust x offset by this, otherwise text will be off-center
// (add 2 to frame's actual offset to prevent leading edge from clipping)
fileprivate let mediaInfoViewLeadingOffset: CGFloat = 20 + 2

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
  private var drawPoint: NSPoint = CGPoint(x: mediaInfoViewLeadingOffset, y: 0)

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
    // Must use superview frame as a reference. NSTextField frame is poorly defined
    let frameWidth = superview!.frame.width
    guard state == .idle && stringWidth >= frameWidth else { return }

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
    drawPoint.x = mediaInfoViewLeadingOffset
    state = .idle
    needsDisplay = true
  }

  @objc
  private func moveText() {
    drawPoint.x -= step
    if drawPoint.x + appendedStringCopyWidth < mediaInfoViewLeadingOffset {
      reset()
      return
    }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let stringWidth = attributedStringValue.size().width
    let frameWidth = superview!.frame.width
    if stringWidth < frameWidth {
      // Plenty of space. Center text instead
      let xOffset = (frameWidth - stringWidth) / 2
      drawPoint.x = xOffset + mediaInfoViewLeadingOffset
      attributedStringValue.draw(at: drawPoint)
    } else {
      scrollingString.draw(at: drawPoint)
    }
  }

}
