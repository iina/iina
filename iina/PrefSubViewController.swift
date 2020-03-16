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

  var preferenceTabImage: NSImage {
    return NSImage(named: NSImage.Name("pref_sub"))!
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

  @IBOutlet weak var subLangTokenView: LanguageTokenField!
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
    loginIndicator.isHidden = true

    subLangTokenView.stringValue = Preference.string(for: .subLang) ?? ""

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
      Utility.quickUsernamePasswordPanel("opensub.login", sheetWindow: self.view.window) { (username, password) in
        self.loginIndicator.isHidden = false
        self.loginIndicator.startAnimation(nil)
        firstly {
          OpenSub.Fetcher.shared.login(testUser: username, password: password)
        }.map { _ in
          do {
            try KeychainAccess.write(username: username, password: password, forService: .openSubAccount)
            Preference.set(username, for: .openSubUsername)
          } catch KeychainAccess.KeychainError.noResult {
            Utility.showAlert("sub.cannot_save_passwd", arguments: ["Cannot find password."], sheetWindow: self.view.window)
          } catch KeychainAccess.KeychainError.unhandledError(let message) {
            Utility.showAlert("sub.cannot_save_passwd", arguments: [message], sheetWindow: self.view.window)
          } catch KeychainAccess.KeychainError.unexpectedData {
            Utility.showAlert("sub.cannot_save_passwd", arguments: ["Unexcepted data when reading password."], sheetWindow: self.view.window)
          }
        }.ensure {
          self.loginIndicator.isHidden = true
          self.loginIndicator.stopAnimation(nil)
        }.catch { err in
          let message: String
          switch err {
          case OpenSub.Error.loginFailed(let reason):
            message = reason
          case OpenSub.Error.xmlRpcError(let e):
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

  @IBAction func preferredLanguageAction(_ sender: LanguageTokenField) {
    Preference.set(sender.stringValue, for: .subLang)
  }

  private func refreshOnlineSubSource() {
    let tag = subSourcePopUpButton.selectedTag()
    for (index, view) in subSourceStackView.views.enumerated() {
      if index == 0 { continue }
      subSourceStackView.setVisibilityPriority(index == tag ? .mustHold : .notVisible, for: view)
    }
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
