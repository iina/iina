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
    KBI(name: "ignore"),
    KBI(name: "seek", type: .label, children:
      KBI(name: "value", type: .string, children:
        KBI.chooseIn("relative|absolute|absolute-percent|relative-percent|exact|keyframes")
      )
    ),
    KBI(name: "set"),
    KBI(name: "cycle")
  ]

  static func load() -> [Criterion] {

    var criterions: [Criterion] = []

    for item in commands {
      criterions.append(item.toCriterion(l10nKey: "cmd"))
    }

    return criterions
  }

}

class KeyBindingItem {

  // MARK: Localization

  static let l10nDic: [String: String] = {
    let filePath = Bundle.main.path(forResource: "KeyBinding", ofType: "strings")!
    let dic = NSDictionary(contentsOfFile: filePath) as! [String : String]
    return dic
  }()

  // MARK: KeyBindingItem

  enum ItemType {
    case label, string, number
  }

  var name: String
  var type: ItemType

  var children: [KeyBindingItem]

  static func chooseIn(_ optionsList: String) -> [KeyBindingItem] {
    let options = optionsList.components(separatedBy: "|")
    var items: [KeyBindingItem] = []
    for op in options {
      items.append(KeyBindingItem(name: op))
    }
    return items
  }

  init(name: String, type: ItemType, children: KeyBindingItem...) {
    self.name = name
    self.type = type
    self.children = children
  }

  init(name: String, type: ItemType, children: [KeyBindingItem]) {
    self.name = name
    self.type = type
    self.children = children
  }

  init(name: String) {
    self.name = name
    self.type = .label
    self.children = []
  }

  init(name: String, type: ItemType) {
    self.name = name
    self.type = type
    self.children = []
  }


  func toCriterion(l10nKey: String? = nil) -> Criterion {
    let criterion: Criterion

    switch type {
    case .label:
      let l10nPath = l10nKey == nil ? name : "\(l10nKey!).\(name)"
      if let l10nString = KeyBindingItem.l10nDic[l10nPath] {
        criterion = TextCriterion(name: l10nString)
      } else {
        criterion = TextCriterion(name: name)
      }
    case .string, .number:
      criterion = TextFieldCriterion()
    }

    if !children.isEmpty {
      for child in children {
        criterion.addChild(child.toCriterion())
      }
    }

    return criterion
  }

}
