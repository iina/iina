//
//  KeyBindingDataLoader.swift
//  iina
//
//  Created by lhc on 4/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate typealias KBI = KeyBindingItem

fileprivate enum PropertyType {
  case bool, num, string, separator
}

class KeyBindingDataLoader {

  fileprivate static let commands: [KeyBindingItem] = [
    KBI("ignore"),
    KBI.separator(),
    KBI("seek", type: .label, children:
      KBI.chooseIn("forward|backward", children:
        KBI("value", type: .number, children:
          KBI.chooseIn("relative|relative-percent|relative+exact|relative-percent+exact")
        )
      )
      +
      KBI.chooseIn("seek-to", children:
        KBI("value", type: .number, children:
          KBI.chooseIn("absolute|absolute-percent|absolute+keyframe|absolute-percent+keyframe")
        )
      )
    ),
    KBI("frame-step"),
    KBI("frame-back-step"),
    KBI("ab-loop"),
    KBI.separator(),
    KBI("set", type: .label, children: propertiesForSet()),
    KBI("cycle", type: .label, children: propertiesForCycle()),
    KBI("cycle-values", type: .label, children: propertiesForCycleValues()),
    KBI("add", type: .label, children: propertiesForAdd()),
    KBI("multiply", type: .label, children: propertiesForMultiply()),
    KBI.separator(),
    KBI("playlist-next"),
    KBI("playlist-prev"),
    KBI("playlist-clear"),
    KBI("playlist-remove"),
    KBI("playlist-shuffle"),
    KBI.separator(),
    KBI("video-panel", type: .iinaCmd),
    KBI("audio-panel", type: .iinaCmd),
    KBI("sub-panel", type: .iinaCmd),
    KBI("playlist-panel", type: .iinaCmd),
    KBI("chapter-panel", type: .iinaCmd),
    KBI.separator(),
    KBI("open-file", type: .iinaCmd),
    KBI("open-url", type: .iinaCmd),
    KBI("save-playlist", type: .iinaCmd),
    KBI("show-current-file-in-finder", type: .iinaCmd),
    KBI("delete-current-file", type: .iinaCmd),
    KBI("delete-current-file-hard", type: .iinaCmd),
    KBI.separator(),
    KBI("find-online-subs", type: .iinaCmd),
    KBI("save-downloaded-sub", type: .iinaCmd),
    KBI.separator(),
    KBI("write-watch-later-config"),
    KBI("stop"),
    KBI("quit")
  ]

  fileprivate static let propertyList: [(String, PropertyType)] = [
    ("pause", .bool),
    ("speed", .num),
    ("---", .separator),
    ("video", .num),
    ("video-aspect", .string),
    ("contrast", .num),
    ("brightness", .num),
    ("gamma", .num),
    ("saturation", .num),
    ("deinterlace", .bool),
    ("---", .separator),
    ("audio", .num),
    ("volume", .num),
    ("mute", .bool),
    ("audio-delay", .num),
    ("---", .separator),
    ("sub", .num),
    ("sub-delay", .num),
    ("sub-pos", .num),
    ("sub-scale", .num),
    ("sub-visibility", .bool),
    ("---", .separator),
    ("fullscreen", .bool),
    ("ontop", .bool),
    ("---", .separator),
    ("chapter", .num)
  ]

  static let toggleableIINAProperties: [String] = [
    "flip", "mirror"
  ]

  static private func propertiesForSet() -> [KeyBindingItem] {
    return propertyList.map { (str, type) -> KeyBindingItem in
      if type == .separator { return KBI.separator() }
      let kbi = KBI(str, type: .label, children:
                  KBI("to", type: .placeholder, children:
                    type == .bool ?
                      KBI.chooseIn("yes|no") :
                      [KBI("value", type: .string)]
                  )
                )
      kbi.l10nKey = "opt"
      return kbi
    }
  }

  static private func propertiesForMultiply() -> [KeyBindingItem] {
    return propertyList.filter { $0.1 != .bool && $0.1 != .string }.map { (str, type) -> KeyBindingItem in
      if type == .separator { return KBI.separator() }
      let kbi = KBI(str, type: .label, children:
                  KBI("by", type: .placeholder, children:
                    KBI("value", type: .string)
                  )
                )
      kbi.l10nKey = "opt"
      return kbi
    }
  }

  static private func propertiesForAdd() -> [KeyBindingItem] {
    return propertyList.filter { $0.1 != .bool && $0.1 != .string }.map { (str, type) -> KeyBindingItem in
      if type == .separator { return KBI.separator() }
      let kbi = KBI(str, type: .label, children:
                  KBI.chooseIn("add|minus", children:
                    KBI("value", type: .string)
                  )
                )
      kbi.l10nKey = "opt"
      return kbi
    }
  }

  static private func propertiesForCycle() -> [KeyBindingItem] {
    var list = propertyList.filter { $0.1 != .string }.map { (str, type) -> KeyBindingItem in
      if type == .separator { return KBI.separator() }
      let kbi = KBI(str)
      kbi.l10nKey = "opt"
      return kbi
    }
    // add properties for iina
    list.append(KBI.separator())
    toggleableIINAProperties.forEach { p in
      let kbi = KBI(p, type: .iinaCmd)
      kbi.l10nKey = "opt"
      list.append(kbi)
    }
    return list
  }

  static private func propertiesForCycleValues() -> [KeyBindingItem] {
    return propertyList.filter { $0.1 != .bool }.map { (str, type) -> KeyBindingItem in
      if type == .separator { return KBI.separator() }
      let kbi = KBI(str, type: .label, children:
        KBI("in", type: .placeholder, children:
          KBI("value", type: .string)
        )
      )
      kbi.l10nKey = "opt"
      return kbi
    }
  }

  static func load() -> [Criterion] {

    var criterions: [Criterion] = []

    for item in commands {
      criterions.append(item.toCriterion(l10nKey: "cmd"))
    }

    return criterions
  }

}

