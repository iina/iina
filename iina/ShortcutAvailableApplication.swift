//
//  ShortcutAvailableApplication.swift
//  iina
//
//  Created by xjbeta on 2017/8/7.
//  Copyright © 2017年 lhc. All rights reserved.
//  http://stackoverflow.com/questions/970707
//

import Cocoa

@objc(ShortcutAvailableApplication)
class ShortcutAvailableApplication: NSApplication {
  override func sendEvent(_ event: NSEvent) {
    
    let commandKey = NSEvent.ModifierFlags.command.rawValue
    let commandShiftKey = NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
    
    if event.type == .keyDown {
      if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue) == commandKey {
        switch event.charactersIgnoringModifiers! {
        case "x":
          if NSApp.sendAction(#selector(NSText.cut(_:)), to:nil, from:self) { return }
        case "c":
          if NSApp.sendAction(#selector(NSText.copy(_:)), to:nil, from:self) { return }
        case "v":
          if NSApp.sendAction(#selector(NSText.paste(_:)), to:nil, from:self) { return }
        case "z":
          if NSApp.sendAction(Selector(("undo:")), to:nil, from:self) { return }
        case "a":
          if NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to:nil, from:self) { return }
        default:
          break
        }
      }
      else if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue) == commandShiftKey {
        if event.charactersIgnoringModifiers == "Z" {
          if NSApp.sendAction(Selector(("redo:")), to:nil, from:self) { return }
        }
      }
    }
    return super.sendEvent(event)
  }
}
