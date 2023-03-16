//
//  KeyMap.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

// Instances of this class are only intended for mpv use. Search the mpv manual for "input.conf".
class KeyMapping: NSObject, Codable {
  static let IINA_PREFIX = "#@iina"

  let isIINACommand: Bool

  var menuItem: NSMenuItem? { nil }

  // MARK: Key

  let rawKey: String

  let normalizedMpvKey: String

  var normalizedMacKey: String? {
    get {
      return KeyCodeHelper.normalizedMacKeySequence(from: normalizedMpvKey)
    }
  }

  // For UI
  var prettyKey: String {
    get {
      if let normalizedMacKey = normalizedMacKey {
        return normalizedMacKey
      } else {
        return normalizedMpvKey
      }
    }
  }

  // MARK: Action

  let action: [String]

  // The action with @iina removed (if applicable), but otherwise not formatted
  let rawAction: String

  // Similar to rawAction, but includes the #@iina prefix if appropriate, and
  // the tokens are always separated by exactly one space
  var readableAction: String {
    get {
      let joined = action.joined(separator: " ")
      return isIINACommand ? ("\(KeyMapping.IINA_PREFIX) " + joined) : joined
    }
  }

  // The human-language description of the action
  var readableCommand: String {
    return KeyBindingTranslator.readableCommand(fromAction: action, isIINACommand: isIINACommand)
  }

  // This is a rare occurrence. The section, if it exists, will be the first element in `action` and will be surrounded by curly braces.
  // Leave it inside `rawAction` and `action` so that it will be easy to edit in the UI.
  var destinationSection: String? {
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

  // The MPV comment
  let comment: String?

  // Convenience method. Returns true if action is "ignore"
  var isIgnored: Bool {
    return rawAction == MPVCommand.ignore.rawValue
  }

  // Serialized form, suitable for writing to a single line of mpv's input.conf
  var confFileFormat: String {
    get {
      let iinaPrefix = isIINACommand ? "\(KeyMapping.IINA_PREFIX) " : ""
      let commentString = (comment == nil || comment!.isEmpty) ? "" : "   #\(comment!)"
      return "\(iinaPrefix)\(rawKey) \(rawAction)\(commentString)"
    }
  }

  // Note: neither `rawKey` nor `rawAction` paranms should start with `KeyMapping.IINA_PREFIX`.
  // (If this is an IINA command, use `isIINACommand: true`)
  init(rawKey: String, rawAction: String, isIINACommand: Bool = false, comment: String? = nil) {
    assert(!rawKey.hasPrefix(KeyMapping.IINA_PREFIX) && !rawAction.hasPrefix(KeyMapping.IINA_PREFIX), "Bad input to KeyMapping init")

    self.rawKey = rawKey
    self.normalizedMpvKey = KeyCodeHelper.normalizeMpv(rawKey)
    self.isIINACommand = isIINACommand
    self.rawAction = rawAction
    self.action = rawAction.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    self.comment = comment
  }

  required convenience init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
    guard let data = propertyList as? Data,
          let row = try? PropertyListDecoder().decode(KeyMapping.self, from: data) else { return nil }
    self.init(rawKey: row.rawKey, rawAction: row.rawAction, isIINACommand: row.isIINACommand, comment: row.comment)
  }


  static func removeIINAPrefix(from string: String) -> String? {
    if string.hasPrefix(IINA_PREFIX) {
      return string[string.index(string.startIndex, offsetBy: IINA_PREFIX.count)...].trimmingCharacters(in: .whitespaces)
    } else {
      return nil
    }
  }

  static func addIINAPrefix(to string: String) -> String {
    "\(KeyMapping.IINA_PREFIX) \(string)"
  }

  public override var description: String {
    return "\(rawKey.quoted) → \(isIINACommand ? "@IINA" : "") \(rawAction.quoted)"
  }

  func rawEquals(_ other: KeyMapping) -> Bool {
    return rawKey == other.rawKey && rawAction == other.rawAction
  }

  // Makes a duplicate of this object, but will also override any non-nil parameter
  func clone(rawKey: String? = nil, rawAction: String? = nil, isIINACommand: Bool? = nil) -> KeyMapping {
    return KeyMapping(rawKey: rawKey ?? self.rawKey,
                      rawAction: rawAction ?? self.rawAction,
                      isIINACommand: isIINACommand ?? self.isIINACommand,
                      comment: self.comment)
  }
}

// Register custom pasteboard type for KeyBinding (for drag&drop, and possibly eventually copy&paste)
extension NSPasteboard.PasteboardType {
  static let iinaKeyMapping = NSPasteboard.PasteboardType("com.colliderli.iina.KeyMapping")
}

extension KeyMapping: NSPasteboardWriting, NSPasteboardReading {
  static func readableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.iinaKeyMapping]
  }
  static func readingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.ReadingOptions {
    return .asData
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.string, .iinaKeyMapping]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    switch type {
      case .string:
        return NSString(utf8String: self.confFileFormat)
      case .iinaKeyMapping:
        return try? PropertyListEncoder().encode(self)
      default:
        return nil
    }
  }

  static func deserializeList(from pasteboard: NSPasteboard) -> [KeyMapping] {
    // Looks for encoded objects first
    if let objList = pasteboard.readObjects(forClasses: [KeyMapping.self], options: nil), !objList.isEmpty {
      return deserializeObjectList(objList)
    }

    // Next looks for strings (if currently allowed)
    if Preference.bool(for: .acceptRawTextAsKeyBindings) {
      return deserializeText(from: pasteboard)
    }
    return []
  }

  static private func deserializeObjectList(_ objList: [Any]) -> [KeyMapping] {
    var mappingList: [KeyMapping] = []
    for obj in objList {
      if let row = obj as? KeyMapping {
        mappingList.append(row)
      } else {
        Logger.log("Found something unexpected from the pasteboard, aborting deserialization: \(type(of: obj))")
        return [] // return empty list if something was amiss
      }
    }
    return mappingList
  }

  static private func deserializeText(from pasteboard: NSPasteboard) -> [KeyMapping] {
    var mappingList: [KeyMapping] = []
    for element in pasteboard.pasteboardItems! {
      if let str = element.string(forType: NSPasteboard.PasteboardType(rawValue: "public.utf8-plain-text")) {
        for rawLine in str.split(separator: "\n") {
          if let mapping = InputConfFile.parseRawLine(String(rawLine)) {
            // If the user dropped a huge e-book into IINA by mistake, try to stop it from blowing up
            if mappingList.count > AppData.maxConfFileLinesAccepted {
              Logger.log("Pasteboard exceeds max allowed bindings from string (\(AppData.maxConfFileLinesAccepted)): aborting", level: .error)
              return []
            }
            mappingList.append(mapping)
          }
        }
      }
    }
    return mappingList
  }
}

// This class is a little bit of a hurried kludge, so that bindings for menu items could go everywhere that mpv's bindings can go,
// but instead of an action string each contains a reference to a menu item.
class MenuItemMapping: KeyMapping {
  private let _menuItem: NSMenuItem
  let sourceName: String
  
  init(rawKey: String, sourceName: String, menuItem: NSMenuItem, actionDescription: String) {
    self._menuItem = menuItem
    self.sourceName = sourceName

    // Store description in `comment`
    super.init(rawKey: rawKey, rawAction: "", isIINACommand: true, comment: actionDescription)
  }

  required init(from decoder: Decoder) throws {
    Logger.fatal("init(from:) is not supported for MenuItemMapping")
  }

  required convenience init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
    fatalError("init(pasteboardPropertyList:ofType:) is not supported for MenuItemMapping")
  }

  public override var description: String {
    return "\(rawKey.quoted) → src=\(sourceName.quoted) menuItem=\(_menuItem.title.quoted) comment=\(comment?.quoted ?? "nil")"
  }

  override var menuItem: NSMenuItem? { _menuItem }

  override var readableAction: String {
    return menuItem?.title ?? ""
  }

  override var readableCommand: String {
    return readableAction
  }
}
