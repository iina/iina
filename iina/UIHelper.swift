//
//  UIHelper.swift
//  iina
//
//  Created by Hechen Li on 2026-06-03.
//  Copyright © 2026 lhc. All rights reserved.
//


class UIHelper {
  static let shared = UIHelper()

  func button(_ key: String, target: NSObject? = nil, action: Selector? = nil) -> NSButton {
    let btn = NSButton(title: localized(key), target: nil, action: nil)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.target = target
    btn.action = action
    return btn
  }

  func input(bindTo key: Preference.Key, fixedAlignmentRect: Bool = true, isFixedSize: Bool = true) -> NSTextField {
    let input = fixedAlignmentRect ? TextFieldWithFixedAlignmentRect() : NSTextField()
    input.translatesAutoresizingMaskIntoConstraints = false
    input.bezelStyle = .roundedBezel
    input.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue)
    if isFixedSize {
      input.size(width: 48, height: 25)
    }
    return input
  }

  func textInput(value: String = "", width: CGFloat = 64) -> NSTextField {
    let textField = NSTextField()
    textField.stringValue = value
    textField.controlSize = .small
    textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    textField.size(width: width)
    return textField
  }

  func label(_ key: String, wrapping: Bool = false, font: NSFont? = nil, isSmall: Bool = false, isSecondary: Bool = false, canCompress: Bool = true) -> NSTextField {
    let textField = if wrapping {
      NSTextField(wrappingLabelWithString: localized(key))
    } else {
      NSTextField(labelWithString: localized(key))
    }
    textField.translatesAutoresizingMaskIntoConstraints = false
    if isSmall {
      textField.controlSize = .small
      textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    }
    if isSecondary {
      textField.textColor = .secondaryLabelColor
    }
    if let font {
      textField.font = font
    }
    if canCompress {
      textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      textField.allowsDefaultTighteningForTruncation = true
      textField.lineBreakMode = .byTruncatingTail
    }
    return textField
  }

  func toggleButton(bindTo key: Preference.Key, size: NSControl.ControlSize = .regular, inverted: Bool = false) -> NSSwitch {
    let btn = NSSwitch()
    btn.controlSize = size
    let opt: [NSBindingOption : Any] = inverted ? [
      .valueTransformerName: NSValueTransformerName(rawValue: "NSNegateBoolean")
    ] : [:]
    btn.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue, options: opt)
    return btn
  }

  func colorWell(bindTo key: Preference.Key) -> NSColorWell {
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
    return hStack(align: align, spacing: LayoutValue(spacing), views)
  }

  func hStack(align: NSLayoutConstraint.Attribute = .centerY, spacing: CGFloat = 8, _ views: [NSView]) -> NSStackView {
    return hStack(align: align, spacing: LayoutValue(spacing), views)
  }

  func hStack(align: NSLayoutConstraint.Attribute = .centerY, spacing: LayoutValue, _ views: NSView...) -> NSStackView {
    return hStack(align: align, spacing: spacing, views)
  }

  func hStack(align: NSLayoutConstraint.Attribute = .centerY, spacing: LayoutValue, _ views: [NSView]) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .horizontal
    stackView.alignment = align
    spacing.use { [weak stackView] in
      stackView?.spacing = $0
    }
    return stackView
  }

  func vStack(align: NSLayoutConstraint.Attribute = .leading, spacing: CGFloat = 8, wantsToGrow: Bool = false, _ views: NSView...) -> NSStackView {
    return vStack(align: align, spacing: LayoutValue(spacing), wantsToGrow: wantsToGrow, views)
  }

  func vStack(align: NSLayoutConstraint.Attribute = .leading, spacing: CGFloat = 8, wantsToGrow: Bool = false, _ views: [NSView]) -> NSStackView {
    return vStack(align: align, spacing: LayoutValue(spacing), wantsToGrow: wantsToGrow, views)
  }

  func vStack(align: NSLayoutConstraint.Attribute = .leading, spacing: LayoutValue, wantsToGrow: Bool = false, _ views: NSView...) -> NSStackView {
    return vStack(align: align, spacing: spacing, wantsToGrow: wantsToGrow, views)
  }

  func vStack(align: NSLayoutConstraint.Attribute = .leading, spacing: LayoutValue, wantsToGrow: Bool = false, _ views: [NSView]) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = align
    spacing.use { [weak stackView] in
      stackView?.spacing = $0
    }
    if wantsToGrow {
      stackView.setHuggingPriority(.init(100), for: .horizontal)
    }
    return stackView
  }

  func space(width: CGFloat = 0, height: CGFloat = 0) -> NSView {
    let view = NSView()
    view.size(width: width, height: height)
    return view
  }

  func flexibleSpace(_ minWidth: CGFloat = 8) -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.size(height: 0)
    view.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return view
  }

  func separator() -> NSBox {
    let box = NSBox(frame: .zero)
    box.translatesAutoresizingMaskIntoConstraints = false
    box.boxType = .separator
    return box
  }

  func image(_ symbol: String..., size: CGFloat = 16, width: CGFloat? = nil, height: CGFloat? = nil,
             config: NSImage.SymbolConfiguration? = nil, scaleUp: Bool = false) -> NSImageView {
    image(
      .sf(symbol, withConfiguration: config) ?? NSImage(named: .init(symbol[0])),
      size: size, width: width, height: height, scaleUp: scaleUp
    )
  }

  func image(_ image: NSImage?, size: CGFloat = 16, width: CGFloat? = nil, height: CGFloat? = nil, scaleUp: Bool = true) -> NSImageView {
    let imageView = NSImageView(image: image ?? .sf("square.split.diagonal.2x2")!)
    imageView.imageScaling = scaleUp ? .scaleProportionallyUpOrDown : .scaleProportionallyDown
    imageView.size(width: width ?? size, height: height ?? size)
    return imageView
  }

  func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: key)
  }

  class TextFieldWithFixedAlignmentRect: NSTextField {
    override func frame(forAlignmentRect alignmentRect: NSRect) -> NSRect {
      return alignmentRect
    }
  }
}
