//
//  LanguageTokenField.swift
//  iina
//
//  Created by Collider LI on 12/4/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

fileprivate class Token: NSObject {
  var content: String
  var code: String

  init(_ content: String) {
    self.content = content
    self.code = ISO639Helper.descriptionRegex.captures(in: content)[at: 1] ?? content
  }
}

class LanguageTokenField: NSTokenField {
  private var layoutManager: NSLayoutManager?

  override func awakeFromNib() {
    super.awakeFromNib()
    self.delegate = self
  }

  override var stringValue: String {
    set {
      self.objectValue = newValue.count == 0 ?
        [] : newValue.components(separatedBy: ",").map(Token.init)
    }
    get {
      return (objectValue as? NSArray)?.map({ val in
        if let token = val as? Token {
          return token.code
        } else if let str = val as? String {
          return str
        }
        return ""
      }).joined(separator: ",") ?? ""
    }
  }

  func controlTextDidChange(_ obj: Notification) {
    guard let layoutManager = layoutManager else { return }
    let attachmentChar = Character(UnicodeScalar(NSTextAttachment.character)!)
    let finished = layoutManager.attributedString().string.split(separator: attachmentChar).count == 0
    if finished, let target = target, let action = action {
      target.performSelector(onMainThread: action, with: self, waitUntilDone: false)
    }
  }

  override func textShouldBeginEditing(_ textObject: NSText) -> Bool {
    if let view = textObject as? NSTextView {
      layoutManager = view.layoutManager
    }
    return true
  }
}

extension LanguageTokenField: NSTokenFieldDelegate {
  func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle {
    return .rounded
  }

  func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
    if let token = representedObject as? Token {
      return token.code
    } else {
      return representedObject as? String
    }
  }

  func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool {
    return false
  }

  func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
    let lowSubString = substring.lowercased()
    let matches = ISO639Helper.languages.filter { lang in
      return lang.name.contains { $0.lowercased().hasPrefix(lowSubString) }
    }
    return matches.map { $0.description }
  }

  func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
    if let token = representedObject as? Token {
      return token.content
    } else {
      return representedObject as? String
    }
  }

  func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
    return Token(editingString)
  }
}
