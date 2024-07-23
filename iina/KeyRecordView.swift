//
//  KeyRecordView.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate extension NSColor {
  static let keyRecordViewBackground = NSColor.controlBackgroundColor.withSystemEffect(.disabled)
  static let keyRecordViewBackgroundActive = NSColor.controlBackgroundColor
}

protocol KeyRecordViewDelegate {
  func keyRecordView(_ view: KeyRecordView, recordedKeyDownWith event: NSEvent)
}

class KeyRecordView: NSView {

  var delegate: KeyRecordViewDelegate!

  var currentKey: String = ""
  var currentKeyModifiers: NSEvent.ModifierFlags = []

  override func awakeFromNib() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.keyRecordViewBackgroundActive.cgColor
    layer?.cornerRadius = 4
  }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.keyRecordViewBackgroundActive.cgColor
  }
  
  override var acceptsFirstResponder: Bool {
    return true
  }

  override func keyDown(with event: NSEvent) {
    currentKey = event.charactersIgnoringModifiers ?? ""
    currentKeyModifiers = event.modifierFlags
    delegate.keyRecordView(self, recordedKeyDownWith: event)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
  }

  override func resignFirstResponder() -> Bool {
    let saved = NSAppearance.current
    NSAppearance.current = self.effectiveAppearance
    layer?.backgroundColor = NSColor.keyRecordViewBackground.cgColor
    NSAppearance.current = saved
    return true
  }

  override func becomeFirstResponder() -> Bool {
    let saved = NSAppearance.current
    NSAppearance.current = self.effectiveAppearance
    layer?.backgroundColor = NSColor.keyRecordViewBackgroundActive.cgColor
    NSAppearance.current = saved
    return true
  }

}
