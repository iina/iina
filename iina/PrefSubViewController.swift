//
//  PrefSubViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PrefSubViewController: NSViewController {

  override var nibName: String? {
    return "PrefSubViewController"
  }

  override var identifier: String? {
    get {
      return "sub"
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage {
    return NSImage(named: NSImageNameFontPanel)!
  }

  var toolbarItemLabel: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.subtitle", comment: "Subtitles")
  }

  var hasResizableWidth: Bool = false
  var hasResizableHeight: Bool = false

  @IBOutlet weak var scrollView: NSScrollView!
  @IBOutlet weak var subLangTokenView: NSTokenField!


  override func viewDidLoad() {
    super.viewDidLoad()

    scrollView.addConstraint(NSLayoutConstraint(item: scrollView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: 420))

    subLangTokenView.delegate = self
  }

  @IBAction func chooseSubFontAction(_ sender: AnyObject) {
    Utility.quickFontPickerWindow { font in
      UserDefaults.standard.set(font ?? "sans-serif", forKey: Preference.Key.subTextFont)
      UserDefaults.standard.synchronize()
    }
  }


}


extension PrefSubViewController: NSTokenFieldDelegate {

  func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenStyle {
    return .rounded
  }

  func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool {
    return false
  }

  func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
    let lowSubString = substring.lowercased()
    let matches = ISO639_2Helper.languages.filter { lang in
      return lang.name.reduce(false) { $1.lowercased().hasPrefix(lowSubString) || $0 }
    }
    return matches.map { $0.description }
  }

  func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any {
    if let code = Regex.iso639_2Desc.captures(in: editingString).at(1) {
      return SubLangToken(code)
    } else {
      return SubLangToken(editingString)
    }
  }

  func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
    if let token = representedObject as? SubLangToken {
      return token.name
    } else {
      return representedObject as? String
    }
  }

}


class SubLangToken: NSObject {
  var name: String

  init(_ name: String) {
    self.name = name
  }

}


@objc(ASSOverrideLevelTransformer) class ASSOverrideLevelTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let num = value as? NSNumber else { return nil }
    return Preference.SubOverrideLevel(rawValue: num.intValue)?.string
  }

}


@objc(SubLangTransformer) class SubLangTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return true
  }

  static override func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let str = value as? NSString else { return nil }
    return str.components(separatedBy: ",")
  }

  override func reverseTransformedValue(_ value: Any?) -> Any? {
    guard let arr = value as? NSArray else { return "" }
    return arr.map{ ($0 as! SubLangToken).name }.joined(separator: ",")
  }
  
}
