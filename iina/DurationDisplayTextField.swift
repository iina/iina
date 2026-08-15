//
//  DurationDisplayView.swift
//  iina
//
//  Created by Christophe Laprun on 26/01/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class DurationDisplayTextField: NSTextField {
  static let framePrecision: UInt = 4
  enum DisplayMode {
    case current
    case duration // displays the duration of the movie
    case remaining // displays the remaining time in the movie
  }

  static var precision : UInt = UInt(Preference.integer(for: .timeDisplayPrecision))
  var mode: DisplayMode = .duration { didSet { updateText() } }
  var duration: VideoTime = .zero
  var current: VideoTime = .zero
  var remaining: VideoTime = .zero
  var frameRate: Double?

  override init(frame frameRect: NSRect) {
    super.init(frame: .zero)
    let fontSize = NSFont.systemFontSize(for: .mini)
    self.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  /** Switches the display mode between duration and remaining time */
  private func switchMode() {
    switch mode {
    case .duration:
      mode = .remaining
    default:
      mode = .duration
    }
  }

  func updateText(with duration: VideoTime, given current: VideoTime,
                  and remaining: VideoTime, frameRate: Double? = nil) {
    self.duration = duration
    self.current = current
    self.remaining = remaining
    self.frameRate = frameRate
    updateText()
  }
  
  private func updateText() {
    let precision = displayPrecision
    let stringValue: String
    switch mode {
    case .current:
      stringValue = current.stringRepresentationWithPrecision(precision, frameRate: frameRate)
    case .duration:
      stringValue = duration.stringRepresentationWithPrecision(precision, frameRate: frameRate)
    case .remaining:
      stringValue = "-\(remaining.stringRepresentationWithPrecision(precision, frameRate: frameRate))"
    }
    self.stringValue = stringValue
  }

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)

    guard mode != .current else { return }
    self.switchMode()
    Preference.set(mode == .remaining, for: .showRemainingTime)
  }

  override func scrollWheel(with event: NSEvent) {
    return
  }

  override func rightMouseDown(with event: NSEvent) {
    let precision = displayPrecision
    let menu = NSMenu(title: "Time label settings")
    menu.addItem(withTitle: NSLocalizedString("osc.precision", comment: "Precision"))
    ["1s", "100ms", "10ms", "1ms"].enumerated().forEach { (index, key) in
      menu.addItem(withTitle: NSLocalizedString("osc.\(key)", comment: ""),
                   action: #selector(self.setPrecision(_:)),
                   target: self, tag: index,
                   stateOn: precision == index)
    }
    if let frameRate, frameRate > 0 {
      menu.addItem(withTitle: NSLocalizedString("osc.1frame", comment: "1 frame"),
                   action: #selector(self.setPrecision(_:)),
                   target: self, tag: Int(Self.framePrecision),
                   stateOn: precision == Self.framePrecision)
    }
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }

  private var displayPrecision: UInt {
    if DurationDisplayTextField.precision == Self.framePrecision && (frameRate ?? 0) <= 0 {
      return 3
    }
    return DurationDisplayTextField.precision
  }

  override func touchesBegan(with event: NSEvent) {
    // handles the remaining time text field in the touch bar
    super.touchesBegan(with: event)

    guard mode != .current else { return }
    self.switchMode()
    Preference.set(mode == .remaining, for: .touchbarShowRemainingTime)
  }

  @objc func setPrecision(_ sender: NSMenuItem) {
    let precision = UInt(sender.tag)
    DurationDisplayTextField.precision = precision
    Preference.set(Int(precision), for: .timeDisplayPrecision)
    PlayerCore.playerCores.forEach { core in
      core.refreshSyncUITimer()
    }
  }
}
