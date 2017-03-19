//
//  PrefSubViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import PromiseKit

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
  @IBOutlet weak var loginIndicator: NSProgressIndicator!

  @IBOutlet weak var fontSizeTextField: NSTextField!
  @IBOutlet weak var fontBlurTextField: NSTextField!
  @IBOutlet weak var fontSpacingTextField: NSTextField!
  @IBOutlet weak var borderSizeTextField: NSTextField!
  @IBOutlet weak var shadowOffsetTextField: NSTextField!
  @IBOutlet weak var positionXTextField: NSTextField!
  @IBOutlet weak var positionYTextField: NSTextField!
  @IBOutlet weak var verticalPositionTextField: NSTextField!

  override func viewDidLoad() {
    super.viewDidLoad()

    scrollView.addConstraint(NSLayoutConstraint(item: scrollView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: 420))

    subLangTokenView.delegate = self
    loginIndicator.isHidden = true

    fontSizeTextField.formatter = RestrictedNumberFormatter(min: 0, isDecimal: false)
    fontBlurTextField.formatter = RestrictedNumberFormatter(min: 0, max: 20, isDecimal: true)
    fontSpacingTextField.formatter = RestrictedNumberFormatter(isDecimal: true)
    borderSizeTextField.formatter = RestrictedNumberFormatter(min: 0, isDecimal: false)
    shadowOffsetTextField.formatter = RestrictedNumberFormatter(min: 0, isDecimal: false)
    positionXTextField.formatter = RestrictedNumberFormatter(isDecimal: false)
    positionYTextField.formatter = RestrictedNumberFormatter(isDecimal: false)
    verticalPositionTextField.formatter = RestrictedNumberFormatter(min: 0, max: 100, isDecimal: false)
  }

  @IBAction func chooseSubFontAction(_ sender: AnyObject) {
    Utility.quickFontPickerWindow { font in
      UserDefaults.standard.set(font ?? "sans-serif", forKey: Preference.Key.subTextFont)
      UserDefaults.standard.synchronize()
    }
  }

  @IBAction func openSubLoginAction(_ sender: AnyObject) {
    let currUsername = UserDefaults.standard.string(forKey: Preference.Key.openSubUsername) ?? ""
    if currUsername.isEmpty {
      // if current username is empty, login
      let _ = Utility.quickUsernamePasswordPanel(messageText: "Opensubtitles Login", informativeText: "Please enter your username and password") {
        (username, password) in
        loginIndicator.isHidden = false
        loginIndicator.startAnimation(nil)
        firstly {
          OpenSubSupport().login(testUser: username, password: password)
        }.then { () -> Void in
          let status = OpenSubSupport.savePassword(username: username, passwd: password)
          if status == errSecSuccess {
            UserDefaults.standard.set(username, forKey: Preference.Key.openSubUsername)
          } else {
            Utility.showAlert(message: "Cannot save your password to Keychain: \(SecCopyErrorMessageString(status, nil))")
          }
        }.always {
          self.loginIndicator.isHidden = true
          self.loginIndicator.stopAnimation(nil)
        }.catch { err in
          let message: String
          switch err {
          case OpenSubSupport.OpenSubError.loginFailed(let reason):
            message = reason
          case OpenSubSupport.OpenSubError.xmlRpcError(let e):
            message = e.readableDescription
          default:
            message = "Unknown error"
          }
          Utility.showAlert(message: "Cannot login. Please check your username, password and network status.\n\n\(message)")
        }
      }
    } else {
      // else, logout
      UserDefaults.standard.set("", forKey: Preference.Key.openSubUsername)
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
    if str.length == 0 { return [] }
    return str.components(separatedBy: ",").map { SubLangToken($0) }
  }

  override func reverseTransformedValue(_ value: Any?) -> Any? {
    guard let arr = value as? NSArray else { return "" }
    return arr.map{ ($0 as! SubLangToken).name }.joined(separator: ",")
  }
  
}


@objc(OpenSubAccountNameTransformer) class OpenSubAccountNameTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    let username = value as? NSString ?? ""
    if username.length == 0 {
      return NSLocalizedString("preference.not_logged_in", comment: "Not logged in")
    } else {
      return String(format: NSLocalizedString("preference.logged_in_as", comment: "Logged in as"), username)
    }
  }
  
}


@objc(LoginButtonTitleTransformer) class LoginButtonTitleTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    let username = value as? NSString ?? ""
    return NSLocalizedString((username.length == 0 ? "login" : "logout"), comment: "")
  }
  
}
