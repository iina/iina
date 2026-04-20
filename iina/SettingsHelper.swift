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

class SettingsUIHelper {
  private var l10n: SettingsLocalization.Context

  init(_ l10n: SettingsLocalization.Context) {
    self.l10n = l10n
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

  func textInput(value: String = "", width: CGFloat = 64) -> NSTextField {
    let textField = NSTextField()
    textField.stringValue = value
    textField.controlSize = .small
    textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    textField.size(width: width)
    return textField
  }

  func label(_ key: SettingsLocalization.Key) -> NSTextField {
    let textField = NSTextField(labelWithString: l10n.localized(key))
    textField.controlSize = .small
    textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    return textField
  }

  func hStack(align: NSLayoutConstraint.Attribute = .firstBaseline, _ views: NSView...) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.orientation = .horizontal
    stackView.alignment = align
    return stackView
  }

  func vStack(_ views: NSView...) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.orientation = .vertical
    stackView.alignment = .leading
    return stackView
  }

  func space(width: CGFloat = 0, height: CGFloat = 0) -> NSView {
    let view = NSView()
    view.size(width: width, height: height)
    return view
  }

  func image(_ symbol: String, size: CGFloat = 16) -> NSImageView {
    let imageView = NSImageView(image: .findSFSymbol([symbol])!)
    imageView.size(width: size, height: size)
    return imageView
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
      view.spacing(to: views[i - 1], .leading(space))
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
      view.spacing(to: views[i - 1], .top(space))
    }
    if let bottom = bottom {
      views.last!.padding(.bottom(bottom))
    }
  }
}
