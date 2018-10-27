//
//  ISO639TokenField.swift
//  iina
//
//  Created by Collider LI on 23/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class ISO639TokenFieldDelegate: NSObject, NSTokenFieldDelegate {

  class Token: NSObject {
    var name: String
    init(_ name: String) {
      self.name = name
    }
  }

  func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle {
    return .rounded
  }

  func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool {
    return false
  }

  func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
    let lowSubString = substring.lowercased()
    let matches = ISO639Helper.languages.filter { lang in
      return lang.name.reduce(false) { $1.lowercased().hasPrefix(lowSubString) || $0 }
    }
    return matches.map { $0.description }
  }

  func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
    if let code = Regex.iso639_2Desc.captures(in: editingString)[at: 1] {
      return Token(code)
    } else {
      return Token(editingString)
    }
  }

  func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
    if let token = representedObject as? Token {
      return token.name
    } else {
      return representedObject as? String
    }
  }

}



@objc(ISO639Transformer) class ISO639Transformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return true
  }

  static override func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let str = value as? NSString else { return nil }
    if str.length == 0 { return [] }
    return str.components(separatedBy: ",").map { ISO639TokenFieldDelegate.Token($0) }
  }

  override func reverseTransformedValue(_ value: Any?) -> Any? {
    guard let arr = value as? NSArray else { return "" }
    return arr.map{ ($0 as! ISO639TokenFieldDelegate.Token).name }.joined(separator: ",")
  }

}
