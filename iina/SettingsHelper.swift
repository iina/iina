//
//  SettingsHelper.swift
//  iina
//
//  Created by Hechen Li on 6/23/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

extension NSTextField {
  @discardableResult
  func makeMultiLine() -> Self {
    self.lineBreakMode = .byWordWrapping
    self.usesSingleLineMode = false
    self.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return self
  }

}

// not sure from which version, need further tests
let topConstraintOffset: CGFloat = if #available(macOS 26, *) { -4 } else { 0 }

class SettingsUIHelper: UIHelper {
  private var l10n: SettingsLocalization.Context

  init(_ l10n: SettingsLocalization.Context) {
    self.l10n = l10n
    super.init()
  }

  func button(_ key: SettingsLocalization.Key) -> NSButton {
    button(key.rawValue)
  }

  func popupButton(_ items: [(SettingsLocalization.Key, Int)]) -> NSPopUpButton {
    let button = NSPopUpButton()
    button.bezelStyle = .accessoryBarAction
    button.controlSize = .small
    button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    for (key, value) in items {
      let item = NSMenuItem()
      item.title = l10n.localized(key)
      item.tag = value
      button.menu!.addItem(item)
    }
    return button
  }

  func smallLabel(bindTo key: SettingsLocalization.Key) -> NSTextField {
    label(key.rawValue, isSmall: true, isSecondary: true)
  }

  func label(bindTo key: SettingsLocalization.Key, isSmall: Bool = false, isSecondary: Bool = false) -> NSTextField {
    label(key.rawValue, isSmall: isSmall, isSecondary: isSecondary)
  }

  override func localized(_ key: String) -> String {
    l10n.localized(.init(key))
  }

  private class RadioTagTransformer: ValueTransformer {
    let tag: Int

    init(tag: Int) {
      self.tag = tag
    }

    override class func transformedValueClass() -> AnyClass { NSNumber.self }
    override class func allowsReverseTransformation() -> Bool { true }

    override func transformedValue(_ value: Any?) -> Any? {
      (value as? Int) == tag ? NSControl.StateValue.on.rawValue
      : NSControl.StateValue.off.rawValue
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
      tag
    }
  }

  func radioGroup(_ prefKey: Preference.Key, size: NSControl.ControlSize = .small, _ items: [(SettingsLocalization.Key, Int)]) -> [NSButton] {
    return items.map { key, value in
      let button = NSButton(radioButtonWithTitle: l10n.localized(key), target: nil, action: nil)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.controlSize = size
      button.bind(.value, to: UserDefaults.standard, withKeyPath: prefKey.rawValue, options: [
        .valueTransformer: RadioTagTransformer(tag: value)
      ])
      return button
    }
  }

  static func hEquallySpaced(_ views: [NSView], _ space: CGFloat = 8, leading: CGFloat? = nil, trailing: CGFloat? = nil) {
    if let leading = leading {
      views.first!.padding(.leading(leading))
    }
    for (i, view) in views.enumerated() {
      if i == 0 { continue }
      view.spacing(.leading(space), to: views[i - 1])
    }
    if let trailing = trailing {
      views.last!.padding(.trailing(greaterThan: trailing))
    }
  }

  static func vEquallySpaced(_ views: [NSView], _ space: CGFloat = 8, top: CGFloat? = nil, bottom: CGFloat? = nil) {
    if let top = top {
      views.first!.padding(.top(top))
    }
    for (i, view) in views.enumerated() {
      if i == 0 { continue }
      view.spacing(.top(space), to: views[i - 1])
    }
    if let bottom = bottom {
      views.last!.padding(.bottom(bottom))
    }
  }
}
