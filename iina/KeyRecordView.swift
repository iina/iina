//
//  KeyRecordView.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

protocol KeyRecordViewDelegate {
  func keyRecordView(_ view: KeyRecordView, recordedKeyDownWith event: NSEvent)
}

class KeyRecordView: NSView {

  var delegate: KeyRecordViewDelegate!

  var currentRawKey: String = ""
  var currentKeyInReadableFormat: String = ""
  var currentKey: String = ""
  var currentKeyModifiers: NSEvent.ModifierFlags = []

  override func awakeFromNib() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.lightGray.cgColor
    layer?.cornerRadius = 4
  }

  override var acceptsFirstResponder: Bool {
    return true
  }

  override func keyDown(with event: NSEvent) {
    currentKey = event.charactersIgnoringModifiers ?? ""
    currentKeyModifiers = event.modifierFlags
    (currentKeyInReadableFormat, currentRawKey) = event.readableKeyDescription
    delegate.keyRecordView(self, recordedKeyDownWith: event)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
  }

  override func resignFirstResponder() -> Bool {
    layer?.backgroundColor = NSColor(calibratedWhite: 0.8, alpha: 1).cgColor
    return true
  }

  override func becomeFirstResponder() -> Bool {
    layer?.backgroundColor = NSColor.lightGray.cgColor
    return true
  }

}
