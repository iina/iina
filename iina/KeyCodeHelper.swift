//
//  KeyCodeHelper.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation
import Carbon

class KeyCodeHelper {
  class KeyEquivalents { // MacOS
    static let BACKSPACE = String(UnicodeScalar(NSBackspaceCharacter)!)
    static let DEL = String(UnicodeScalar(NSDeleteCharacter)!)
    static let ENTER = String(UnicodeScalar(NSEnterCharacter)!)
    static let RETURN = String(UnicodeScalar(NSNewlineCharacter)!)
  }

  // mpv modifiers in normal form:
  static let CTRL_KEY = "Ctrl"
  static let ALT_KEY = "Alt"
  static let SHIFT_KEY = "Shift"
  static let META_KEY = "Meta"

  fileprivate static let modifierOrder: [String: Int] = [
    CTRL_KEY: 0,
    ALT_KEY: 1,
    SHIFT_KEY: 2,
    META_KEY: 3
  ]

  fileprivate static let modifierSymbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
  fileprivate static let modifierFlagsToMpv: [(NSEvent.ModifierFlags, String)] = [(.control, CTRL_KEY), (.option, ALT_KEY), (.shift, SHIFT_KEY), (.command, META_KEY)]

  static let keyMap: [UInt16 : (String, String?)] = [
    0x00: ("a", "A"),
    0x01: ("s", "S"),
    0x02: ("d", "D"),
    0x03: ("f", "F"),
    0x04: ("h", "H"),
    0x05: ("g", "G"),
    0x06: ("z", "Z"),
    0x07: ("x", "X"),
    0x08: ("c", "C"),
    0x09: ("v", "V"),
    0x0B: ("b", "B"),
    0x0C: ("q", "Q"),
    0x0D: ("w", "W"),
    0x0E: ("e", "E"),
    0x0F: ("r", "R"),
    0x10: ("y", "Y"),
    0x11: ("t", "T"),
    0x12: ("1", "!"),
    0x13: ("2", "@"),
    0x14: ("3", "SHARP"),
    0x15: ("4", "$"),
    0x16: ("6", "^"),
    0x17: ("5", "%"),
    0x18: ("=", "+"),
    0x19: ("9", "("),
    0x1A: ("7", "&"),
    0x1B: ("-", "_"),
    0x1C: ("8", "*"),
    0x1D: ("0", ")"),
    0x1E: ("]", "}"),
    0x1F: ("o", "O"),
    0x20: ("u", "U"),
    0x21: ("[", "{"),
    0x22: ("i", "I"),
    0x23: ("p", "P"),
    0x25: ("l", "L"),
    0x26: ("j", "J"),
    0x27: ("'", "\"\"\""),
    0x28: ("k", "K"),
    0x29: (";", ":"),
    0x2A: ("\"\\\"", "|"),
    0x2B: (",", "<"),
    0x2C: ("/", "?"),
    0x2D: ("n", "N"),
    0x2E: ("m", "M"),
    0x2F: (".", ">"),
    0x32: ("`", "~"),
    0x41: ("KP_DEC", nil),
    0x43: ("*", nil),
    0x45: ("+", nil),
    // 0x47: ("KeypadClear", nil),
    0x4B: ("/", nil),
    0x4C: ("KP_ENTER", nil),
    0x4E: ("-", nil),
    0x51: ("=", nil),
    0x52: ("KP0", nil),
    0x53: ("KP1", nil),
    0x54: ("KP2", nil),
    0x55: ("KP3", nil),
    0x56: ("KP4", nil),
    0x57: ("KP5", nil),
    0x58: ("KP6", nil),
    0x59: ("KP7", nil),
    0x5B: ("KP8", nil),
    0x5C: ("KP9", nil),

    0x24: ("ENTER", nil),
    0x30: ("TAB", nil),
    0x31: ("SPACE", nil),
    0x33: ("BS", nil),
    0x35: ("ESC", nil),
    // 0x37: ("Command", nil),
    // 0x38: ("Shift", nil),
    // 0x39: ("CapsLock", nil),
    // 0x3A: ("Option", nil),
    // 0x3B: ("Control", nil),
    // 0x3C: ("RightShift", nil),
    // 0x3D: ("RightOption", nil),
    // 0x3E: ("RightControl", nil),
    // 0x3F: ("Function", nil),
    0x40: ("F17", nil),
    // 0x48: ("VolumeUp", nil),
    // 0x49: ("VolumeDown", nil),
    // 0x4A: ("Mute", nil),
    0x4F: ("F18", nil),
    0x50: ("F19", nil),
    0x5A: ("F20", nil),
    0x60: ("F5", nil),
    0x61: ("F6", nil),
    0x62: ("F7", nil),
    0x63: ("F3", nil),
    0x64: ("F8", nil),
    0x65: ("F9", nil),
    0x67: ("F11", nil),
    0x69: ("F13", nil),
    0x6A: ("F16", nil),
    0x6B: ("F14", nil),
    0x6D: ("F10", nil),
    0x6F: ("F12", nil),
    0x71: ("F15", nil),
    0x72: ("INS", nil),
    0x73: ("HOME", nil),
    0x74: ("PGUP", nil),
    0x75: ("DEL", nil),
    0x76: ("F4", nil),
    0x77: ("END", nil),
    0x78: ("F2", nil),
    0x79: ("PGDWN", nil),
    0x7A: ("F1", nil),
    0x7B: ("LEFT", nil),
    0x7C: ("RIGHT", nil),
    0x7D: ("DOWN", nil),
    0x7E: ("UP", nil),
    0x7F: ("POWER", nil) // This should be KeyCode::PC_POWER.
  ]

  static let mpvSymbolToKeyChar: [String: String] = {

    return [
      "LEFT": NSLeftArrowFunctionKey,
      "RIGHT": NSRightArrowFunctionKey,
      "UP": NSUpArrowFunctionKey,
      "DOWN": NSDownArrowFunctionKey,
      "BS": NSBackspaceCharacter,
      "KP_DEL": NSDeleteCharacter,
      "DEL": NSDeleteCharacter,
      "KP_INS": NSInsertFunctionKey,
      "INS": NSInsertFunctionKey,
      "HOME": NSHomeFunctionKey,
      "END": NSEndFunctionKey,
      "PGUP": NSPageUpFunctionKey,
      "PGDWN": NSPageDownFunctionKey,
      "PRINT": NSPrintFunctionKey,
      "F1": NSF1FunctionKey,
      "F2": NSF2FunctionKey,
      "F3": NSF3FunctionKey,
      "F4": NSF4FunctionKey,
      "F5": NSF5FunctionKey,
      "F6": NSF6FunctionKey,
      "F7": NSF7FunctionKey,
      "F8": NSF8FunctionKey,
      "F9": NSF9FunctionKey,
      "F10": NSF10FunctionKey,
      "F11": NSF11FunctionKey,
      "F12": NSF12FunctionKey
    ]
    .mapValues { String(Character(UnicodeScalar($0)!)) }
    .merging([
      "SPACE": " ",
      "IDEOGRAPHIC_SPACE": "\u{3000}",
      "SHARP": "#",
      "ENTER": "\r",
      "ESC": "\u{1b}",
      "KP_DEC": ".",
      "KP_ENTER": "\r",
      "KP0": "0",
      "KP1": "1",
      "KP2": "2",
      "KP3": "3",
      "KP4": "4",
      "KP5": "5",
      "KP6": "6",
      "KP7": "7",
      "KP8": "8",
      "KP9": "9",
      "PLUS": "+"
    ]) { (v0, v1) in return v1 }

  }()

  static let mpvSymbolToKeyName: [String: String] = [
    META_KEY: "⌘",
    SHIFT_KEY: "⇧",
    ALT_KEY: "⌥",
    CTRL_KEY:"⌃",
    "SHARP": "#",
    "ENTER": "↩︎",
    "KP_ENTER": "↩︎",
    "SPACE": "␣",
    "IDEOGRAPHIC_SPACE": "␣",
    "BS": "⌫",
    "DEL": "⌦",
    "KP_DEL": "⌦",
    "INS": "Ins",
    "KP_INS": "Ins",
    "TAB": "⇥",
    "ESC": "⎋",
    "UP": "↑",
    "DOWN": "↓",
    "LEFT": "←",
    "RIGHT" : "→",
    "PGUP": "⇞",
    "PGDWN": "⇟",
    "HOME": "↖︎",
    "END": "↘︎",
    "PLAY": "▶︎\u{2006}❙\u{200A}❙",
    "PREV": "◀︎◀︎",
    "NEXT": "▶︎▶︎",
    "PLUS": "+",
    "KP0": "0",
    "KP1": "1",
    "KP2": "2",
    "KP3": "3",
    "KP4": "4",
    "KP5": "5",
    "KP6": "6",
    "KP7": "7",
    "KP8": "8",
    "KP9": "9",
  ]

  static var reversedKeyMapForShift: [String: String] = keyMap.reduce([:]) { partial, keyMap in
    var partial = partial
    if let value = keyMap.value.1 {
      partial[value] = keyMap.value.0
    }
    return partial
  }

  static func canBeModifiedByShift(_ key: UInt16) -> Bool {
    return key != 0x24 && (key <= 0x2F || key == 0x32)
  }

  static func isPrintable(_ char: String) -> Bool {
    let utf8View = char.utf8
    return utf8View.count == 1 && utf8View.first! > 32 && utf8View.first! < 127
  }

  static func escapeReservedMpvKeys(_ keystrokesString: String) -> String {
    // "#" and " " are not valid for `rawKey` because are reserved as tokens when parsing the conf file.
    // Try to help the user out a little bit before rejecting
    if keystrokesString == " " {
      return "SPACE"
    }
    var keystrokesSplit: [String] = KeyCodeHelper.splitKeystrokes(keystrokesString.trimmingCharacters(in: .whitespaces))
    for (i, rawKey) in keystrokesSplit.enumerated() {
      if rawKey == " " {
        keystrokesSplit[i] = "SPACE"
      } else if rawKey == "#" {
        keystrokesSplit[i] = "SHARP"
      }
    }
    return keystrokesSplit.joined(separator: "-")
  }

  static func mpvKeyCode(from event: NSEvent) -> String {
    var keyString = ""
    let keyChar: String
    let keyCode = event.keyCode
    var modifiers = event.modifierFlags

    if let char = event.charactersIgnoringModifiers, isPrintable(char) {
      keyChar = char
      // The char in `charactersIgnoringModifiers` should always include shift info.
      modifiers.remove(.shift)
    } else {
      // find the key from key code
      guard let keyName = KeyCodeHelper.keyMap[keyCode] else {
        Logger.log("Undefined key code: \"\(keyCode)\"", level: .warning)
        return ""
      }
      keyChar = keyName.0
    }
    // modifiers
    // the same order as `KeyCodeHelper.modifierOrder`
    if modifiers.contains(.control) {
      keyString += "\(CTRL_KEY)+"
    }
    if modifiers.contains(.option) {
      keyString += "\(ALT_KEY)+"
    }
    if modifiers.contains(.shift) {
      keyString += "\(SHIFT_KEY)+"
    }
    if modifiers.contains(.command) {
      keyString += "\(META_KEY)+"
    }
    // char
    keyString += keyChar
    return keyString
  }

  // Finds and returns the end index of the next key in the string
  private static func getNextEndIndex(_ unparsedRemainder: Substring) -> String.Index? {
    if let dashIndex = unparsedRemainder.firstIndex(of: "-"),
     let indexBeyondDash = unparsedRemainder.index(dashIndex, offsetBy: 1, limitedBy: unparsedRemainder.index(before: unparsedRemainder.endIndex)) { // There is a '-' somewhere, and there is at least 1 char after it
      if dashIndex == unparsedRemainder.startIndex {
        guard unparsedRemainder[indexBeyondDash] == "-" else {
          return nil
        }
        // Next char is '-' and should be treated like a key, but needs to be terminated
        return indexBeyondDash
      } else {
        // The '-' should be treated like a separator char
        return dashIndex
      }
    }
    // No '-' in string, or it is the only char in the string: use whole string as the next key
    return unparsedRemainder.endIndex
  }

  // See mpv/input/keycodes.c: mp_input_get_keys_from_string()
  public static func splitKeystrokes(_ keystrokes: String) -> [String] {
    // Older versions of IINA's saved filters would add 3 null chars to end before saving in IINA's preferences.
    // They will cause matching logic to fail, so it's necessary to check for this for the forseeable future.
    let ksClean = keystrokes.replacingOccurrences(of: "\0", with: "")
    if ksClean.count != keystrokes.count {
      Logger.log("Found \(keystrokes.count - ksClean.count) null characters in \"\(keystrokes)\"; will try to fix & continue", level: .warning)
    }
    var unparsedRemainder = Substring(ksClean)
    var splitKeystrokeList: [String] = []

    while !unparsedRemainder.isEmpty && splitKeystrokeList.count < MP_MAX_KEY_DOWN {
      guard let endIndex = getNextEndIndex(unparsedRemainder) else {
        Logger.log("Could not split keystrokes; not a valid sequence: \"\(keystrokes)\"", level: .warning)
        return [keystrokes]
      }

      let ks = String(unparsedRemainder[unparsedRemainder.startIndex..<endIndex])
      guard !ks.isEmpty else {
          Logger.log("While splitting keystrokes: Last keystroke is empty! Returning list: \(splitKeystrokeList)", level: .error)
          return splitKeystrokeList
      }
      splitKeystrokeList.append(ks)

      guard let indexBeyondEnd = unparsedRemainder.index(endIndex, offsetBy: 1, limitedBy: unparsedRemainder.endIndex) else {
        break
      }

      unparsedRemainder = unparsedRemainder[indexBeyondEnd...]
    }
    return splitKeystrokeList
  }

  // Normalizes a single "press" of possibly multiple keys (as joined with '+')
  private static func normalizeSingleMpvKeystroke(_ mpvKeystroke: String) -> String {
    if mpvKeystroke == "+" {
      return mpvKeystroke
    }
    var normalizedList: [String] = []
    let splitted = mpvKeystroke.replacingOccurrences(of: "++", with: "+PLUS").components(separatedBy: "+")
    var key = splitted.last!
    splitted.dropLast().forEach { k in
      // Modifiers have first letter capitalized. All other special chars are capitalized
      if k.equalsIgnoreCase(SHIFT_KEY) {
        // For chars with upper & lower cases, remove the "Shift+" and replace with actual uppercase char
        if key.count == 1, key.lowercased() != key.uppercased() {
          key = key.uppercased()
        } else {
          normalizedList.append(SHIFT_KEY)
        }
      } else if k.equalsIgnoreCase(META_KEY) {
        normalizedList.append(META_KEY)
      } else if k.equalsIgnoreCase(CTRL_KEY) {
        normalizedList.append(CTRL_KEY)
      } else if k.equalsIgnoreCase(ALT_KEY) {
        normalizedList.append(ALT_KEY)
      } else {
        normalizedList.append(k.uppercased())
      }
    }
    if key.count > 1 {
      // assume it's a special char
      key = key.uppercased()
    }
    normalizedList.append(key)

    normalizedList = normalizedList.sorted { modifierOrder[$0, default: 9] < modifierOrder[$1, default: 9] }
    return normalizedList.joined(separator: "+")
  }

  public static func splitAndNormalizeMpvString(_ mpvKeystrokes: String) -> [String] {
    // this is a hard-coded special case in mpv
    if mpvKeystrokes == "default-bindings" {
      return [mpvKeystrokes]
    }
    let keystrokesList = splitKeystrokes(mpvKeystrokes)

    var normalizedList: [String] = []
    for keystroke in keystrokesList {
      normalizedList.append(normalizeSingleMpvKeystroke(keystroke))
    }
    return normalizedList
  }

  /*
   Several forms for the same keystroke are accepted by mpv. This ensures that it is reduced to a single standardized form
   (such that it can be used in a set or map, and which matches what `mpvKeyCode()` returns).

   Definitions used here:
   - A "key" is just any individual key on a keyboard (including keyboards from different locales around the world).
   - A "keystroke" for our purposes is any combination of up to 4 different keys which are held down simultaneously, of which only one is a
     "regular" (non-modifier) key, and the rest are "modifier keys". Note that currently we don't enforce the restriction on only one regular key.
   - The 4 "modifier keys" include: "Meta" (aka Command), "Ctrl", "Alt" (aka Option), "Shift"
   - A "key sequence" is an ordered list of up to 4 keystrokes. Whereas a "keystroke" is a set of keys typed in parallel, a "key sequence" is a set
     of keystrokes typed serially.

   Normal Form Rules:
   1. If the key is matches the exact string "default-bindings", assume it is part of the special line "default-bindings start",
      and return it as-is.
   2. The input string is parsed as a sequence of up to 4 keystrokes, each of which is separated by the character "-".
      Note that "-" is itself a valid keystroke, so that e.g. this is a valid 4-key sequence: "-------"
   3. Each resulting keystroke shall be parsed into up to 4 keys, each of which is separated by the character "+".
      Note that the "+" character is accepted as a valid key, but it is normalized to "PLUS".
   4. Each of the 4 modifiers shall be written with the first letter in uppercase and the remaining letters in lowercase.
   5. There always shall be exactly 1 "regular" key in each keystroke, and it is always the last key in the keystroke.
   6. A keystroke can contain between 0 and 3 modifiers (up to 1 of each kind).
   7. The modifiers, if present, shall respect the following order from left to right: "Ctrl", "Alt", "Shift", "Meta"
      (e.g., "Meta+Ctrl+J" is invalid, but "Ctrl+Alt+DEL" is valid)
   8. If the regular key in the keystroke is of the set of characters which have separate and distinct uppercase and lowercase versions, then
      the keystroke shall never contain an explicit "Shift" modifier but instead shall use the uppercase character.
   9. Any remaining special keys not previously mentioned and which have more than one character in their name shall be written in all uppercase.
      (examples: SHARP, SPACE, PGDOWN)
   */
  public static func normalizeMpv(_ mpvKeystrokes: String) -> String {
    let normalizedList = splitAndNormalizeMpvString(mpvKeystrokes)
    return normalizedList.joined(separator: "-")
  }

  // Converts an mpv-formatted key string to a (key, modifiers) pair suitable for assignment to a MacOS menu item.
  // IMPORTANT: `mpvKeyCode` must be normalized first! Use `KeyCodeHelper.normalizeMpv()`.
  static func macOSKeyEquivalent(from mpvKeyCode: String, usePrintableKeyName: Bool = false) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
    if mpvKeyCode == "default-bindings" {
      return nil
    }
    let keystrokeList = splitKeystrokes(mpvKeyCode)
    if keystrokeList.count > 1 {
      Logger.log("macOSKeyEquivalent(): found more than one keystroke in input string: \"\(mpvKeyCode)\"", level: .error)
    }
    let splitted = keystrokeList[0].components(separatedBy: "+")
    var key: String
    var modifiers: NSEvent.ModifierFlags = []
    guard !splitted.isEmpty else { return nil }
    key = splitted.last!
    splitted.dropLast().forEach { k in
      switch k {
      case META_KEY: modifiers.insert(.command)
      case CTRL_KEY: modifiers.insert(.control)
      case ALT_KEY: modifiers.insert(.option)
      case SHIFT_KEY: modifiers.insert(.shift)
      default: break
      }
    }
    if let realKey = (usePrintableKeyName ? mpvSymbolToKeyName : mpvSymbolToKeyChar)[key] {
      key = realKey
    }
    guard key.count == 1 else { return nil }
    return (key, modifiers)
  }

  // Formats a MacOS (key, modifiers) pair into a MacOS-formatted display string.
  static func readableString(fromKey key: String, modifiers: NSEvent.ModifierFlags) -> String {
    var key = key
    var modifiers = modifiers
    if let uScalar = key.first?.unicodeScalars.first, NSCharacterSet.uppercaseLetters.contains(uScalar) {
      modifiers.insert(.shift)
    }
    key = key.uppercased()
    return modifierSymbols.map { modifiers.contains($0.0) ? $0.1 : "" }
      .joined()
      .appending(key)
  }

  static func macString(from modifiers: NSEvent.ModifierFlags) -> String {
    return modifierSymbols.map { modifiers.contains($0.0) ? $0.1 : "" }
      .joined()
  }

  // Formats a string of one or more keystrokes from mpv form to Mac form
  // IMPORTANT: `mpvKeyCode` must be normalized first! Use `KeyCodeHelper.normalizeMpv()`.
  static func normalizedMacKeySequence(from normalizedMpvKeySequence: String) -> String {
    if normalizedMpvKeySequence == "default-bindings" {
      return normalizedMpvKeySequence
    }
    var macKeyList: [String] = []
    let keystrokes = splitKeystrokes(normalizedMpvKeySequence)
    for keystroke in keystrokes {
      if let (keyChar, modifiers) = KeyCodeHelper.macOSKeyEquivalent(from: keystroke, usePrintableKeyName: true) {
        macKeyList.append(KeyCodeHelper.readableString(fromKey: keyChar, modifiers: modifiers))
      } else {
        // Probabaly a weird key. Just pass it through
        macKeyList.append(keystroke)
      }
    }
    return macKeyList.joined(separator: ", ")
  }

  static func macOSToMpv(key: String, modifiers: NSEvent.ModifierFlags) -> String {
    var mpvTokens: [String] = []
    for (modifierFlag, mpvModifier) in modifierFlagsToMpv {
      if modifiers.contains(modifierFlag) {
        mpvTokens.append(mpvModifier)
      }
    }

    // MacOS key equivalents always display single characters in uppercase, but mpv will interpret this as adding "Shift".
    // If there is supposed to be a Shift key pressed, it will have been in the modifier flags above,
    // and converted to explicit "+Shift".
    let cleanKey = key.count == 1 ? key.lowercased() : key
    mpvTokens.append(cleanKey)
    return mpvTokens.joined(separator: "+")
  }
}


fileprivate let NSEventKeyCodeMapping: [Int: String] = [
  kVK_F1: "F1",
  kVK_F2: "F2",
  kVK_F3: "F3",
  kVK_F4: "F4",
  kVK_F5: "F5",
  kVK_F6: "F6",
  kVK_F7: "F7",
  kVK_F8: "F8",
  kVK_F9: "F9",
  kVK_F10: "F10",
  kVK_F11: "F11",
  kVK_F12: "F12",
  kVK_F13: "F13",
  kVK_F14: "F14",
  kVK_F15: "F15",
  kVK_F16: "F16",
  kVK_F17: "F17",
  kVK_F18: "F18",
  kVK_F19: "F19",
  kVK_Space: "␣",
  kVK_Escape: "⎋",
  kVK_Delete: "⌦",
  kVK_ForwardDelete: "⌫",
  kVK_LeftArrow: "←",
  kVK_RightArrow: "→",
  kVK_UpArrow: "↑",
  kVK_DownArrow: "↓",
  kVK_Help: "",
  kVK_PageUp: "⇞",
  kVK_PageDown: "⇟",
  kVK_Tab: "⇥",
  kVK_Return: "⏎",
  kVK_ANSI_Keypad0: "0",
  kVK_ANSI_Keypad1: "1",
  kVK_ANSI_Keypad2: "2",
  kVK_ANSI_Keypad3: "3",
  kVK_ANSI_Keypad4: "4",
  kVK_ANSI_Keypad5: "5",
  kVK_ANSI_Keypad6: "6",
  kVK_ANSI_Keypad7: "7",
  kVK_ANSI_Keypad8: "8",
  kVK_ANSI_Keypad9: "9",
  kVK_ANSI_KeypadDecimal: ".",
  kVK_ANSI_KeypadMultiply: "*",
  kVK_ANSI_KeypadPlus: "+",
  kVK_ANSI_KeypadClear: "Clear",
  kVK_ANSI_KeypadDivide: "/",
  kVK_ANSI_KeypadEnter: "↩︎",
  kVK_ANSI_KeypadMinus: "-",
  kVK_ANSI_KeypadEquals: "="
]
