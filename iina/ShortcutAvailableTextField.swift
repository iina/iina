//
//  ShortcutAvailableTextField.swift
//  iina
//
//  Created by lhc on 26/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//  http://stackoverflow.com/questions/970707
//

import Cocoa

class ShortcutAvailableTextField: NSTextField {

  private let commandKey = NSEvent.ModifierFlags.command
  
  private let commandShiftKey = [NSEvent.ModifierFlags.command, NSEvent.ModifierFlags.shift]

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.type == .keyDown {
      if [event.modifierFlags, NSEvent.ModifierFlags.deviceIndependentFlagsMask] == commandKey {
        switch event.charactersIgnoringModifiers! {
        case "x":
          if NSApp.sendAction(#selector(NSText.cut(_:)), to:nil, from:self) { return true }
        case "c":
          if NSApp.sendAction(#selector(NSText.copy(_:)), to:nil, from:self) { return true }
        case "v":
          if NSApp.sendAction(#selector(NSText.paste(_:)), to:nil, from:self) { return true }
        case "z":
          if NSApp.sendAction(Selector(("undo:")), to:nil, from:self) { return true }
        case "a":
          if NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to:nil, from:self) { return true }
        default:
          break
        }
      }
      else if [event.modifierFlags, NSEvent.ModifierFlags.deviceIndependentFlagsMask] == commandShiftKey {
        if event.charactersIgnoringModifiers == "Z" {
          if NSApp.sendAction(Selector(("redo:")), to:nil, from:self) { return true }
        }
      }
    }
    return super.performKeyEquivalent(with: event)
  }

}
