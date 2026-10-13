//
//  IINAApplication.swift
//  iina
//

import Cocoa

/// IINA's `NSApplication` subclass, set as `NSPrincipalClass` in Info.plist.
@objc(IINAApplication)
class IINAApplication: NSApplication {

  /// Delivers numpad key presses to the key player window before the menu bar can intercept them.
  ///
  /// Menu item key equivalents are matched app-wide before the player window's `keyDown`, and
  /// `NSMenuItem` cannot represent numpad keys, so a number-row key equivalent would also match its
  /// numpad twin and run the wrong action when the two keys have different bindings (#4898).
  /// Numpad key bindings are handled by the player window, so when a numpad key with a binding is
  /// pressed while a player window is key, send it to the window directly.
  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown,
       let window = IINAApplication.routingWindow(keyWindow: keyWindow, mainWindow: mainWindow),
       IINAApplication.isBoundNumpadKeyEvent(event) {
      window.sendEvent(event)
      return
    }
    super.sendEvent(event)
  }

  /// Returns the player window a numpad key event should be delivered to, or `nil` to use normal dispatch.
  ///
  /// When the app is inactive there is no key window; programmatically delivered
  /// events (Accessibility, automation) should still reach the player window. A window with
  /// an attached sheet is waiting for dialog input, so it must not receive playback commands.
  static func routingWindow(keyWindow: NSWindow?, mainWindow: NSWindow?) -> NSWindow? {
    guard let window = keyWindow ?? mainWindow,
          window.attachedSheet == nil,
          window.windowController is PlayerWindowController else { return nil }
    return window
  }

  /// Returns whether the event is a numpad key press that has a key binding.
  ///
  /// The binding can be the key's own, or come from the number-row fallback in
  /// `PlayerCore.keyBinding(for:)`. Arrow keys also carry the `.numericPad` flag
  /// and are excluded by requiring an mpv `KP*` key name.
  static func isBoundNumpadKeyEvent(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.numericPad),
          let keyName = KeyCodeHelper.keyMap[event.keyCode]?.0, keyName.hasPrefix("KP") else {
      return false
    }
    let normalizedKeyCode = KeyCodeHelper.normalizeMpv(KeyCodeHelper.mpvKeyCode(from: event))
    return PlayerCore.keyBinding(for: normalizedKeyCode) != nil
  }
}
