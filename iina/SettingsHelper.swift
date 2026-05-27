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

class SettingsUIHelper {
  private var l10n: SettingsLocalization.Context

  init(_ l10n: SettingsLocalization.Context) {
    self.l10n = l10n
  }

  func button(_ key: SettingsLocalization.Key) -> NSButton {
    let btn = NSButton(title: l10n.localized(key), target: nil, action: nil)
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
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

  func input(_ key: Preference.Key, fixedAlignmentRect: Bool = true, isFixedSize: Bool = true) -> NSTextField {
    let input = fixedAlignmentRect ? TextFieldWithFixedAlignmentRect() : NSTextField()
    input.translatesAutoresizingMaskIntoConstraints = false
    input.bezelStyle = .roundedBezel
    input.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
    if isFixedSize {
      input.size(width: 48, height: 25)
    }
    return input
  }

  func label(_ key: SettingsLocalization.Key, isSmall: Bool = true, isSecondary: Bool = true) -> NSTextField {
    let textField = NSTextField(labelWithString: l10n.localized(key))
    textField.translatesAutoresizingMaskIntoConstraints = false
    if isSmall {
      textField.controlSize = .small
      textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    }
    if isSecondary {
      textField.textColor = .secondaryLabelColor
    }
    return textField
  }

  func colorWell(_ key: Preference.Key) -> NSColorWell {
    let colorWell = NSColorWell()
    colorWell.translatesAutoresizingMaskIntoConstraints = false
    if #available(macOS 13.0, *) {
      colorWell.colorWellStyle = .expanded
    } else {
      colorWell.size(width: 30)
    }
    colorWell.size(height: 24)
    colorWell.bind(.value, to: UserDefaults.standard,
                   withKeyPath: key.rawValue,
                   options: [.valueTransformer: MPVColorStringTransformer()])
    return colorWell
  }

  func hStack(align: NSLayoutConstraint.Attribute = .centerY, spacing: CGFloat = 8, _ views: NSView...) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .horizontal
    stackView.alignment = align
    stackView.spacing = spacing
    return stackView
  }

  func vStack(align: NSLayoutConstraint.Attribute = .leading, spacing: CGFloat = 8, _ views: NSView...) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = align
    stackView.spacing = spacing
    return stackView
  }

  func space(width: CGFloat = 0, height: CGFloat = 0) -> NSView {
    let view = NSView()
    view.size(width: width, height: height)
    return view
  }

  func image(_ symbol: String, size: CGFloat = 16) -> NSImageView {
    let imageView = NSImageView(image: .sf(symbol)!)
    imageView.size(width: size, height: size)
    return imageView
  }

  fileprivate class TextFieldWithFixedAlignmentRect: NSTextField {
    override func frame(forAlignmentRect alignmentRect: NSRect) -> NSRect {
      return alignmentRect
    }
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
