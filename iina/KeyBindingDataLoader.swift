//
//  KeyBindingDataLoader.swift
//  iina
//
//  Created by lhc on 4/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate typealias KBI = KeyBindingItem

class KeyBindingDataLoader {

  static let commands: [KeyBindingItem] = [
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
    KBI.separator(),
    KBI("set", type: .label, children: propertiesForSet()),
    KBI("cycle", type: .label, children: propertiesForCycle()),
    KBI("add", type: .label, children: propertiesForAdd()),
    KBI("multiply", type: .label, children: propertiesForMultiply()),
    KBI.separator(),
    KBI("playlist-next"),
    KBI("playlist-prev"),
    KBI("playlist-clear"),
    KBI("playlist-remove"),
    KBI("playlist-shuffle"),
    KBI.separator(),
    KBI("write-watch-later-config"),
    KBI("stop"),
    KBI("quit")
  ]

  static let propertyList: [String] = [
    "pause",
    "volume", "mute",
    "speed",
    "fullscreen",
    "sub-delay", "sub-pos", "sub-scale"
  ]

  static private func propertiesForSet() -> [KeyBindingItem] {
    return propertyList.map { str -> KeyBindingItem in
      let kbi = KBI(str, type: .label, children:
                  KBI("to", type: .placeholder, children:
                    KBI("value", type: .string)
                  )
                )
      kbi.l10nKey = "opt"
      return kbi
    }
  }

  static private func propertiesForMultiply() -> [KeyBindingItem] {
    return propertyList.map { str -> KeyBindingItem in
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
    return propertyList.map { str -> KeyBindingItem in
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
    return propertyList.map { str -> KeyBindingItem in
      let kbi = KBI(str)
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

