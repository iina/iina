//
//  KeyMap.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

fileprivate let IINA_PREFIX = "@iina"
fileprivate let IINA_PREFIX_IN_FILE = "#" + IINA_PREFIX

/// mpv input.conf binding modifier. The default `.command` is a plain
/// `KEY ACTION` row. `.click` / `.press` / `.release` correspond to
/// mpv's `#@click` / `#@press` / `#@release` suffix on the action,
/// which lets the same physical key emit different commands depending
/// on the input event (single click, long press, key release).
/// See `.specite/iterations/mpv-config-driven-refactor/SPEC.md`
/// requirement 8 / PLAN Phase 5.
enum BindingKind: String {
  case command
  case click
  case press
  case release

  /// The `#@<rawValue>` token written to `input.conf`, or empty for
  /// the default `.command` kind (no suffix emitted).
  var confSuffix: String {
    switch self {
    case .command: return ""
    default: return "#@" + rawValue
    }
  }
}

class KeyMapping: NSObject {

  // TODO: this is UI logic. Move it out of here.
  @objc var keyForDisplay: String {
    get {
      if Preference.bool(for: .displayKeyBindingRawValues) {
        return rawKey
      } else {
        if let (keyChar, modifiers) = KeyCodeHelper.macOSKeyEquivalent(from: normalizedMpvKey, usePrintableKeyName: true) {
          return KeyCodeHelper.readableString(fromKey: keyChar, modifiers: modifiers)
        } else {
          return normalizedMpvKey
        }
      }
    }
    set {
      rawKey = newValue
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
    }
  }

  // TODO: this is UI logic. Move it out of here.
  /// When highlighting, the text will become color due to `NSColor.selectedTextColor`.
  /// Since we have a custom NSBox underneath the text, we don't want the text field
  /// to change color to selected text color. The only way to prevent the system from
  /// changing color is use `NSAttributedString` in the text field.
  var attributedKeyForDisplay: NSAttributedString {
      NSAttributedString(
          string: keyForDisplay,
          attributes: [.foregroundColor: NSColor.textColor]
      )
  }

  // TODO: this is UI logic. Move it out of here.
  @objc var actionForDisplay: String {
    get {
      return Preference.bool(for: .displayKeyBindingRawValues) ? readableAction : prettyCommand
    }
    set {
      rawAction = newValue
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
    }
  }

  var isIINACommand: Bool

  /// mpv binding modifier for this row. `.command` is the default
  /// (plain `KEY ACTION`); `.click` / `.press` / `.release` correspond
  /// to mpv's `#@<kind>` action suffix. Defaults to `.command` so the
  /// vast majority of rows (and all pre-existing call sites) behave
  /// exactly as before.
  let binding: BindingKind

  var rawKey: String {
    didSet {
      self.normalizedMpvKey = KeyCodeHelper.normalizeMpv(rawKey)
    }
  }

  private(set) var normalizedMpvKey: String

  // This is a rare occurrence. The section, if it exists, will be the first element in `action` and will be surrounded by curly braces.
  // Leave it inside `rawAction` and `action` so that it will be easy to edit in the UI.
  var section: String? {
    get {
      if action.count > 1 && action[0].count > 0 && action[0][action[0].startIndex] == "{" {
        if let endIndex = action[0].firstIndex(of: "}") {
          let inner = action[0][action[0].index(after: action[0].startIndex)..<endIndex]
          return inner.trimmingCharacters(in: .whitespaces)
        }
      }
      return nil
    }
  }

  private(set) var action: [String]

  private var privateRawAction: String

  var rawAction: String {
    set {
      if newValue.hasPrefix(IINA_PREFIX) {
        privateRawAction = newValue[newValue.index(newValue.startIndex,
                                                   offsetBy: IINA_PREFIX.count)...].trimmingCharacters(in: .whitespaces)
        isIINACommand = true
      } else {
        privateRawAction = newValue
        isIINACommand = false
      }
      action = privateRawAction.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }
    get {
      return privateRawAction
    }
  }

  var comment: String?

  @objc var readableAction: String {
    get {
      let joined = action.joined(separator: " ")
      return isIINACommand ? ("\(IINA_PREFIX) " + joined) : joined
    }
  }

  @objc var prettyCommand: String {
    return KeyBindingTranslator.readableCommand(fromAction: action, isIINACommand: isIINACommand)
  }

  var confFileFormat: String {
    get {
      let iinaCommandString = isIINACommand ? "\(IINA_PREFIX_IN_FILE) " : ""
      // Emit the `#@<kind>` suffix only for non-default bindings so
      // round-tripping through `generateInputConf` preserves click /
      // press / release semantics.
      let bindingSuffix = binding.confSuffix.isEmpty ? "" : " \(binding.confSuffix)"
      let commentString = (comment == nil || comment!.isEmpty) ? "" : "   #\(comment!)"
      return "\(iinaCommandString)\(rawKey) \(action.joined(separator: " "))\(bindingSuffix)\(commentString)"
    }
  }

  init(rawKey: String, rawAction: String, isIINACommand: Bool = false, comment: String? = nil, binding: BindingKind = .command) {
    self.rawKey = rawKey
    self.normalizedMpvKey = KeyCodeHelper.normalizeMpv(rawKey)
    self.isIINACommand = isIINACommand
    self.comment = comment
    self.binding = binding
    self.privateRawAction = rawAction
    self.action = rawAction.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
  }

  public override var description: String {
    return "KeyMapping(\"\(rawKey)\"->\"\(action.joined(separator: " "))\" iina=\(isIINACommand) binding=\(binding.rawValue))"
  }

  // MARK: Static functions

  // Returns nil if cannot read file
  static func parseInputConf(at path: String) -> [KeyMapping]? {
    guard let reader = StreamReader(path: path) else {
      return nil
    }
    var mapping: [KeyMapping] = []
    while var line: String = reader.nextLine() {      // ignore empty lines
      var isIINACommand = false
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        continue
      } else if line.hasPrefix("#") {
        if line.hasPrefix(IINA_PREFIX_IN_FILE) {
          // extended syntax
          isIINACommand = true
          line = String(line[line.index(line.startIndex, offsetBy: IINA_PREFIX_IN_FILE.count)...])
        } else {
          // ignore comment line
          continue
        }
      }
      var comment: String? = nil
      // SPEC Phase 5 / requirement 8: detect mpv's `#@click` / `#@press` /
      // `#@release` action-suffix BEFORE the comment-split step below.
      // The suffix appears at end of line as a separate token
      // (e.g. "SPACE cycle pause                  #@click"); without
      // this pre-check the comment-split would swallow `#@click` into
      // the `comment` field and the binding kind would be lost.
      // We scan the trimmed tail for any of the three known suffixes;
      // on a match we record the kind and strip the suffix (plus any
      // preceding whitespace) from `line` so the subsequent key/action
      // split produces a clean action. A regular comment may still
      // follow on the same line and is handled by the comment-split
      // below as usual.
      var bindingKind: BindingKind = .command
      let trimmedTail = line.trimmingCharacters(in: .whitespaces)
      for kind in [BindingKind.click, .press, .release] {
        let suffix = "#@" + kind.rawValue
        if trimmedTail.hasSuffix(suffix) {
          bindingKind = kind
          if let suffixRange = line.range(of: suffix, options: .backwards) {
            line = String(line[..<suffixRange.lowerBound])
          }
          break
        }
      }
      if let sharpIndex = line.firstIndex(of: "#") {
        comment = String(line[line.index(after: sharpIndex)...])
        line = String(line[...line.index(before: sharpIndex)])
      }
      // split
      let splitted = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t"})
      if splitted.count < 2 {
        Logger.log("Skipped corrupted line in input.conf: \(line)", level: .warning)
        continue  // no command, wrong format
      }
      let key = String(splitted[0]).trimmingCharacters(in: .whitespaces)
      let action = String(splitted[1]).trimmingCharacters(in: .whitespaces)

      mapping.append(KeyMapping(rawKey: key, rawAction: action, isIINACommand: isIINACommand, comment: comment, binding: bindingKind))
    }
    return mapping
  }

  static func generateInputConf(from mappings: [KeyMapping]) -> String {
    return mappings.reduce("# Generated by IINA\n\n", { prevLines, km in prevLines + "\(km.confFileFormat)\n" })
  }
}
