//
//  SavedFilter.swift
//  iina
//
//  Created by Collider LI on 8/12/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let ModifierMap: [Character: NSEvent.ModifierFlags] = [
  "c": .control,
  "o": .option,
  "s": .shift,
  "m": .command
]


class SavedFilter: NSObject {

  @objc var name: String
  @objc var filterString: String
  @objc var readableShortCutKey: String {
    get {
      return ([(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")] as [(NSEvent.ModifierFlags, String)])
        .map { shortcutKeyModifiers.contains($0.0) ? $0.1 : "" }
        .joined()
        .appending(shortcutKey.uppercased())
    }
  }
  @objc var isEnabled = false
  var shortcutKey: String
  var shortcutKeyModifiers: NSEvent.ModifierFlags

  override var debugDescription: String {
    Mirror(reflecting: self).children.map({"\($0.label!)=\($0.value)"}).joined(separator: ", ")
  }

  init(name: String, filterString: String, shortcutKey: String, modifiers: NSEvent.ModifierFlags) {
    self.name = name
    self.filterString = filterString
    self.shortcutKey = shortcutKey
    self.shortcutKeyModifiers = modifiers
  }

  init?(dict: Any) {
    guard let dict = dict as? [String: String],
      let name = dict["name"],
      let filterString = dict["filterString"],
      let shortcutKey = dict["shortcutKey"],
      let shortcutKeyModifiers = dict["shortcutKeyModifiers"] else { return nil }
    self.name = name
    self.filterString = filterString
    self.shortcutKey = shortcutKey
    self.shortcutKeyModifiers = shortcutKeyModifiers.compactMap { ModifierMap[$0] }.reduce([]) { $0.union($1) }
  }

  func toDict() -> [String: String] {
    return [
      "name": name,
      "filterString": filterString,
      "shortcutKey": shortcutKey,
      "shortcutKeyModifiers": String(ModifierMap.enumerated().compactMap { shortcutKeyModifiers.contains($0.element.value) ? $0.element.key : nil })
    ]
  }
}
