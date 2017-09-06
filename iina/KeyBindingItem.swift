//
//  KeyBindingItem.swift
//  iina
//
//  Created by lhc on 4/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class KeyBindingItem {

  // MARK: KeyBindingItem

  enum ItemType {
    case label, iinaCmd, string, number, placeholder, separator
  }

  var name: String
  var type: ItemType

  var l10nKey: String?

  var children: [KeyBindingItem]

  static func chooseIn(_ optionsList: String) -> [KeyBindingItem] {
    let options = optionsList.components(separatedBy: "|")
    var items: [KeyBindingItem] = []
    for op in options {
      items.append(KeyBindingItem(op))
    }
    return items
  }

  static func chooseIn(_ optionsList: String, children: KeyBindingItem...) -> [KeyBindingItem] {
    let options = optionsList.components(separatedBy: "|")
    var items: [KeyBindingItem] = []
    for op in options {
      items.append(KeyBindingItem(op, type: .label, children: children))
    }
    return items
  }

  static func separator() -> KeyBindingItem {
    return KeyBindingItem("---", type: .separator)
  }

  init(_ name: String, type: ItemType, children: KeyBindingItem...) {
    self.name = name
    self.type = type
    self.children = children
  }

  init(_ name: String, type: ItemType, children: [KeyBindingItem]) {
    self.name = name
    self.type = type
    self.children = children
  }

  init(_ name: String) {
    self.name = name
    self.type = .label
    self.children = []
  }

  init(_ name: String, type: ItemType) {
    self.name = name
    self.type = type
    self.children = []
  }


  func toCriterion(l10nKey: String? = nil) -> Criterion {
    let criterion: Criterion

    switch type {
    case .label, .placeholder, .iinaCmd:
      let k = type == .iinaCmd ? "iina" : (l10nKey ?? self.l10nKey)
      let l10nPath = k == nil ? name : "\(k!).\(name)"
      if let l10nString = KeyBindingTranslator.l10nDic[l10nPath] {
        criterion = TextCriterion(name: name, localizedName: l10nString)
      } else {
        criterion = TextCriterion(name: name, localizedName: name)
      }
      if type == .placeholder {
        criterion.isPlaceholder = true
      } else if type == .iinaCmd {
        criterion.isIINACommand = true
      }
    case .string, .number:
      criterion = TextFieldCriterion()
    case .separator:
      criterion = SeparatorCriterion()
    }

    if !children.isEmpty {
      for child in children {
        criterion.addChild(child.toCriterion())
      }
    }
    
    return criterion
  }
  
}
