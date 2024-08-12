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

  @IBOutlet var subColorWell: NSColorWell!
  @IBOutlet var subBackgroundColorWell: NSColorWell!
  @IBOutlet var subBorderColorWell: NSColorWell!
  @IBOutlet var subShadowColorWell: NSColorWell!

  override func viewDidLoad() {
    super.viewDidLoad()

#if MACOS_13_AVAILABLE
    if #available(macOS 13.0, *) {
      [subColorWell, subBackgroundColorWell, subBorderColorWell, subShadowColorWell].forEach {
        $0.colorWellStyle = .expanded
      }
    }
#endif

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

    subLangTokenView.commaSeparatedValues = Preference.string(for: .subLang) ?? ""

    refreshSubSources()
    refreshSubSourceAccessoryView()

    NotificationCenter.default.addObserver(forName: .iinaPluginChanged, object: nil, queue: .main) { [unowned self] _ in
      self.refreshSubSources()
    }
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
    refreshSubSourceAccessoryView()
  }

  @IBAction func preferredLanguageAction(_ sender: LanguageTokenField) {
    let csv = sender.commaSeparatedValues
    if Preference.string(for: .subLang) != csv {
      Logger.log("Saving \(Preference.Key.subLang.rawValue): \"\(csv)\"", level: .verbose)
      Preference.set(csv, for: .subLang)
    }
  }

  private func refreshSubSources() {
    OnlineSubtitle.populateMenu(subSourcePopUpButton.menu!)
    let provider = Preference.string(for: .onlineSubProvider)
    let index = subSourcePopUpButton.menu!.items.firstIndex { $0.representedObject as? String == provider }
    subSourcePopUpButton.selectItem(at: index ?? 0)
  }

  private func refreshSubSourceAccessoryView() {
    let map = [OnlineSubtitle.Providers.openSub.id: 1, OnlineSubtitle.Providers.assrt.id: 2]
    let id = subSourcePopUpButton.selectedItem?.representedObject as? String ?? ""
    for (index, view) in subSourceStackView.views.enumerated() {
      if index == 0 { continue }
      subSourceStackView.setVisibilityPriority(index == map[id] ? .mustHold : .notVisible, for: view)
    }
  }
}

// MARK: - Transformers

@objc(ASSOverrideLevelTransformer) class ASSOverrideLevelTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let num = value as? NSNumber,
          let level = Preference.SubOverrideLevel(rawValue: num.intValue) else { return nil }
    switch level {
    case .yes:
      return NSLocalizedString("preference.sub_override_level.yes", value: "yes", comment: "yes")
    case .force:
      return NSLocalizedString("preference.sub_override_level.force", value: "force", comment: "force")
    case .strip:
      return NSLocalizedString("preference.sub_override_level.strip", value: "strip", comment: "strip")
    case .scale:
      return NSLocalizedString("preference.sub_override_level.scale", value: "scale", comment: "scale")
    case .no:
      return NSLocalizedString("preference.sub_override_level.no", value: "no", comment: "no")
    }
  }
}

/// Transform a raw `SubOverrideLevel` enum value into a slider value.
///
/// Normally there is a 1 to 1 mapping between an enum value and a slider value. However this is not true for `SubOverrideLevel`.
/// Originally the only supported values for the `Override level` setting were `yes`, `force` and `strip`. Then `scale` and
/// `no` were added. The order for the slider now _must_ be `no`, `yes`, `scale`, `force` and `strip`. But to preserve
/// backward compatibility with enum values stored in user's settings `scale` and `no` were added to the end of the enumeration,
/// thus requiring a transformation between the slider and enum values as shown in this table:
///
/// | Slider | Raw | Enum |
/// | --- | --- | --- |
/// | 0 | 4 | no |
/// | 1 | 0 | yes |
/// | 2 | 3 | scale |
/// | 3 | 1 | force |
/// | 4 | 2 | strip |
@objc(ASSOverrideLevelValueTransformer) class ASSOverrideLevelValueTransformer: ValueTransformer {

  private static let enumToSlider: [NSNumber: NSNumber] = [0: 1, 1: 3, 2: 4, 3: 2, 4:0]

  private static let sliderToEnum: [NSNumber: NSNumber] = {
    var result: [NSNumber: NSNumber] = [:]
    for (raw, slider) in enumToSlider { result[slider] = raw }
    return result
  }()

  override class func allowsReverseTransformation() -> Bool { true }

  override func reverseTransformedValue(_ value: Any?) -> Any? {
    guard let value = toNumber(value) else { return nil }
    return ASSOverrideLevelValueTransformer.sliderToEnum[value]
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let value = toNumber(value) else { return nil }
    return ASSOverrideLevelValueTransformer.enumToSlider[value]
  }

  override class func transformedValueClass() -> AnyClass { NSNumber.self }

  private func toNumber(_ value: Any?) -> NSNumber? {
    guard let value = value as? NSNumber else {
      guard let value = value as? NSString else { return nil }
      return value.integerValue as NSNumber
    }
    return value
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

@objc(MPVColorStringTransformer) class MPVColorStringTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return true
  }

  static override func transformedValueClass() -> AnyClass {
    return NSString.self
  }

  // Serializes an NSColor to an mpv-recognized string
  override func transformedValue(_ value: Any?) -> Any? {
    guard let mpvColorString = value as? NSString else { return nil }
    return NSColor(mpvColorString: String(mpvColorString))
  }

  override func reverseTransformedValue(_ value: Any?) -> Any? {
    guard let color = value as? NSColor else { return nil }
    return color.usingColorSpace(.deviceRGB)!.mpvColorString
  }
}
