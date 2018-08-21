//
//  PrefSubViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import PromiseKit

@objcMembers
class PrefSubViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefSubViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.subtitle", comment: "Subtitles")
  }

  override var sectionViews: [NSView] {
    return [sectionAutoLoadView, sectionASSView, sectionTextSubView, sectionPositionView, sectionOnlineSubView, sectionOtherView]
  }

  @IBOutlet var sectionAutoLoadView: NSView!
  @IBOutlet var sectionASSView: NSView!
  @IBOutlet var sectionTextSubView: NSView!
  @IBOutlet var sectionPositionView: NSView!
  @IBOutlet var sectionOnlineSubView: NSView!
  @IBOutlet var sectionOtherView: NSView!

  @IBOutlet weak var subSourceStackView: NSStackView!
  @IBOutlet weak var subSourcePopUpButton: NSPopUpButton!

  @IBOutlet weak var subLangTokenView: NSTokenField!
  @IBOutlet weak var loginIndicator: NSProgressIndicator!
  @IBOutlet weak var defaultEncodingList: NSPopUpButton!

  override func viewDidLoad() {
    super.viewDidLoad()
    
    let defaultEncoding = Preference.string(for: .defaultEncoding)
    for encoding in AppData.encodings {
      defaultEncodingList.addItem(withTitle: encoding.title)
      let lastItem = defaultEncodingList.lastItem!
      lastItem.representedObject = encoding.code
      if encoding.code == defaultEncoding ?? "auto" {
        defaultEncodingList.select(lastItem)
      }
    }
    
    defaultEncodingList.menu?.insertItem(NSMenuItem.separator(), at: 1)

    subLangTokenView.delegate = self
    loginIndicator.isHidden = true

    refreshOnlineSubSource()
  }

  @IBAction func chooseSubFontAction(_ sender: AnyObject) {
    Utility.quickFontPickerWindow { font in
      Preference.set(font ?? "sans-serif", for: .subTextFont)
      UserDefaults.standard.synchronize()
    }
  }

  @IBAction func openSubLoginAction(_ sender: AnyObject) {
    let currUsername = Preference.string(for: .openSubUsername) ?? ""
    if currUsername.isEmpty {
      // if current username is empty, login
      let _ = Utility.quickUsernamePasswordPanel("opensub.login") {
        (username, password) in
        loginIndicator.isHidden = false
        loginIndicator.startAnimation(nil)
        firstly {
          OpenSubSupport().login(testUser: username, password: password)
        }.map { _ in
          let status = OpenSubSupport.savePassword(username: username, passwd: password)
          if status == errSecSuccess {
            Preference.set(username, for: .openSubUsername)
          } else {
            Utility.showAlert("sub.cannot_save_passwd", arguments: [SecCopyErrorMessageString(status, nil) as! CVarArg],
                              sheetWindow: self.view.window)
          }
        }.ensure {
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
          Utility.showAlert("sub.cannot_login", arguments: [message], sheetWindow: self.view.window)
        }
      }
    } else {
      // else, logout
      Preference.set("", for: .openSubUsername)
    }
  }
  
  @IBAction func changeDefaultEncoding(_ sender: NSPopUpButton) {
    Preference.set(sender.selectedItem!.representedObject!, for: .defaultEncoding)
    PlayerCore.active.setSubEncoding((sender.selectedItem?.representedObject as? String) ?? "auto")
    PlayerCore.active.reloadAllSubs()
  }
  
  @IBAction func openSubHelpBtnAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink.appending("/Download-Online-Subtitles#opensubtitles"))!)
  }

  @IBAction func assrtHelpBtnAction(_ sender: AnyObject) {
    NSWorkspace.shared.open(URL(string: AppData.wikiLink.appending("/Download-Online-Subtitles#assrt"))!)
  }

  @IBAction func onlineSubSourceAction(_ sender: NSPopUpButton) {
    refreshOnlineSubSource()
  }

  private func refreshOnlineSubSource() {
    let tag = subSourcePopUpButton.selectedTag()
    for (index, view) in subSourceStackView.views.enumerated() {
      if index == 0 { continue }
      subSourceStackView.setVisibilityPriority(index == tag ? .mustHold : .notVisible, for: view)
    }
  }
}


extension PrefSubViewController: NSTokenFieldDelegate {

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
    return NSLocalizedString((username.length == 0 ? "general.login" : "general.logout"), comment: "")
  }
  
}
